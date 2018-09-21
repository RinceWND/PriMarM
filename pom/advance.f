! advance.f

! advance POM

!_______________________________________________________________________
      subroutine advance
        use seaice
! advance POM 1 step in time
      implicit none
      include 'pom.h'

! get time
      call get_time

! set time dependent surface boundary conditions
      call surface_forcing

! set lateral viscosity
      call lateral_viscosity

! form vertical averages of 3-D fields for use in external (2-D) mode
      call mode_interaction

! external (2-D) mode calculation
      do iext=1,isplit
        call mode_external
        call check_nan_2d  !fhx:tide:debug
        if (calc_ice) call ice_advance
      end do

! internal (3-D) mode calculation
      call mode_internal

! print section
      call print_section

! check nan
      call check_nan

! store mean 2010/4/26
      call store_mean

! store SURF mean
      call store_surf_mean  !fhx:20110131:

! write output
!      call write_output( dtime )

! write restart
!      if(mod(iint,irestart).eq.0) call write_restart_pnetcdf

! check CFL condition
      call check_velocity

      return
      end

!_______________________________________________________________________
      subroutine get_time
! return the model time
      implicit none
      include 'pom.h'
      time=dti*float(iint)/86400.+time0
      ramp=1.
!      if(lramp) then
!        ramp=time/period
!        if(ramp.gt.1.e0) ramp=1.e0
!      else
!        ramp=1.e0
!      endif
      return
      end

!_______________________________________________________________________
      subroutine surface_forcing
! set time dependent surface boundary conditions
      implicit none
      include 'pom.h'
      integer i,j
      real(kind=rk) tatm,satm

      do j=1,jm
        do i=1,im

! wind stress
! value is negative for westerly or southerly winds. The wind stress
! should be tapered along the boundary to suppress numerically induced
! oscilations near the boundary (Jamart and Ozer, JGR, 91, 10621-10631)
!          wusurf(i,j)=0.e0
!     test ayumi 2010/5/8
!          wusurf(i,j) = 2.e-4
!     $     * cos( pi *( north_e(i,j) - 10.e0 ) / 40.e0 )

!          wvsurf(i,j)=0.e0

!          e_atmos(i,j)=0.
!          vfluxf(i,j)=0.e0

! set w(i,j,1)=vflux(i,j).ne.0 if one wishes non-zero flow across
! the sea surface. See calculation of elf(i,j) below and subroutines
! vertvl, advt1 (or advt2). If w(1,j,1)=0, and, additionally, there
! is no net flow across lateral boundaries, the basin volume will be
! constant; if also vflux(i,j).ne.0, then, for example, the average
! salinity will change and, unrealistically, so will total salt
          w(i,j,1)=vfluxf(i,j)

! set wtsurf to the sensible heat, the latent heat (which involves
! only the evaporative component of vflux) and the long wave
! radiation

! ayumi 2010/4/19
! wtsurf & wssurf are calculated in tsclim_monthly
!          wtsurf(i,j)=0.e0

! set swrad to the short wave radiation
!          swrad(i,j)=0.e0

! to account for change in temperature of flow crossing the sea
! surface (generally quite small compared to latent heat effect)
          tatm=t(i,j,1)+tbias    ! an approximation
!          wtsurf(i,j)=wtsurf(i,j)+vfluxf(i,j)*(tatm-t(i,j,1)-tbias)

! set the salinity of water vapor/precipitation which enters/leaves
! the atmosphere (or e.g., an ice cover)
          satm=0.
!          wssurf(i,j)=            vfluxf(i,j)*(satm-s(i,j,1)-sbias)

        end do
      end do

      return
      end

!_______________________________________________________________________
      subroutine lateral_viscosity
! set the lateral viscosity
      implicit none
      include 'pom.h'
      integer i,j,k
! if mode=2 then initial values of aam2d are used. If one wishes
! to use Smagorinsky lateral viscosity and diffusion for an
! external (2-D) mode calculation, then appropiate code can be
! adapted from that below and installed just before the end of the
! "if(mode.eq.2)" loop in subroutine advave

! calculate Smagorinsky lateral viscosity:
! ( hor visc = horcon*dx*dy*sqrt((du/dx)**2+(dv/dy)**2
!                                +.5*(du/dy+dv/dx)**2) )
      if(mode.ne.2) then
        call advct(a,c,ee)

        call pgscheme(npg)

!lyo:scs1d:
        if (n1d.ne.0) then
        aam(:,:,:)=aam_init
        else
!
        do k=1,kbm1
          do j=2,jmm1
            do i=2,imm1
              aam(i,j,k)=horcon*dx(i,j)*dy(i,j)*aamfac(i,j)       !fhx:incmix
     $                    *sqrt( ((u(i+1,j,k)-u(i,j,k))/dx(i,j))**2
     $                          +((v(i,j+1,k)-v(i,j,k))/dy(i,j))**2
     $                    +.5*(.25*(u(i,j+1,k)+u(i+1,j+1,k)
     $                                 -u(i,j-1,k)-u(i+1,j-1,k))
     $                    /dy(i,j)
     $                    +.25*(v(i+1,j,k)+v(i+1,j+1,k)
     $                           -v(i-1,j,k)-v(i-1,j+1,k))
     $                    /dx(i,j)) **2)
            end do
          end do
        end do

        endif !lyo:scs1d:
!
! create sponge zones
!        do k=1,kbm1
!          do j=2,jmm1
!            do i=2,imm1
!              aam(i,j,k)=aam(i,j,k)+1000*exp(-(j_global(j)-2)*1.5)
!     $                    +1000*exp((j_global(j)-jm_global+1)*1.5)
!            end do
!          end do
!        end do

        call exchange3d_mpi(aam(:,:,1:kbm1),im,jm,kbm1)
      end if

      return
      end

!_______________________________________________________________________
      subroutine mode_interaction
! form vertical averages of 3-D fields for use in external (2-D) mode
      implicit none
      include 'pom.h'
      integer i,j,k

      if(mode.ne.2) then

        do j=1,jm
          do i=1,im
            adx2d(i,j)=0.
            ady2d(i,j)=0.
            drx2d(i,j)=0.
            dry2d(i,j)=0.
            aam2d(i,j)=0.
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=1,im
              adx2d(i,j)=adx2d(i,j)+advx(i,j,k)*dz(k)
              ady2d(i,j)=ady2d(i,j)+advy(i,j,k)*dz(k)
              drx2d(i,j)=drx2d(i,j)+drhox(i,j,k)*dz(k)
              dry2d(i,j)=dry2d(i,j)+drhoy(i,j,k)*dz(k)
              aam2d(i,j)=aam2d(i,j)+aam(i,j,k)*dz(k)
            end do
          end do
        end do

        call advave(tps)

        do j=1,jm
          do i=1,im
            adx2d(i,j)=adx2d(i,j)-advua(i,j)
            ady2d(i,j)=ady2d(i,j)-advva(i,j)
          end do
        end do

      end if

      do j=1,jm
        do i=1,im
          egf(i,j)=el(i,j)*ispi
        end do
      end do

      do j=1,jm
        do i=2,im
          utf(i,j)=ua(i,j)*(d(i,j)+d(i-1,j))*isp2i
        end do
      end do
      do j=2,jm
        do i=1,im
          vtf(i,j)=va(i,j)*(d(i,j)+d(i,j-1))*isp2i
        end do
      end do

      return
      end

!_______________________________________________________________________
      subroutine mode_external
! calculate the external (2-D) mode
      use module_time

      implicit none
      include 'pom.h'
      integer i,j

      integer       :: t_is
      real(kind=rk) :: t_jd,t_id,t_L0,t_L1,t_s_l,t_s_r,t_s_b
      type(date) d_now

      d_now = str2date( time_start ) + int(time*86400)
      call update_vars(d_now,t_jd,t_id,t_is,t_L0,t_L1,t_s_l,t_s_r,t_s_b)

      do j=1,jm
        do i=1,im
          call sungrav(north_c(i,j),east_c(i,j),t_jd,t_id,t_is
     &                ,rot(i,j),Fu_S(i,j),Fv_S(i,j),Fw_S(i,j))
          call moongrav(north_c(i,j),east_c(i,j),t_jd,t_LO,t_L1
     &                 ,t_s_l, t_s_r, t_s_b, t_id, t_is
     &                 ,rot(i,j),Fu_M(i,j),Fv_M(i,j),Fw_M(i,j))
        end do
      end do

      do j=2,jm
        do i=2,im
          fluxua(i,j)=.25*(d(i,j)+d(i-1,j))
     $                 *(dy(i,j)+dy(i-1,j))*ua(i,j)
          fluxva(i,j)=.25*(d(i,j)+d(i,j-1))
     $                 *(dx(i,j)+dx(i,j-1))*va(i,j)
        end do
      end do

! NOTE addition of surface freshwater flux, w(i,j,1)=vflux, compared
! with pom98.f. See also modifications to subroutine vertvl
      do j=2,jmm1
        do i=2,imm1
          elf(i,j)=elb(i,j)
     $              +dte2*(-(fluxua(i+1,j)-fluxua(i,j)
     $                      +fluxva(i,j+1)-fluxva(i,j))/art(i,j)
     $                      -vfluxf(i,j))
!          elf(i,j) = elf(i,j) + (Fw_S(i,j)+Fw_M(i,j))/grav
        end do
      end do

      call bcond(1)

      call exchange2d_mpi(elf,im,jm)
      call exchange2d_mpi(Fu_S,im,jm)
      call exchange2d_mpi(Fv_S,im,jm)
      call exchange2d_mpi(Fw_S,im,jm)
      call exchange2d_mpi(Fu_M,im,jm)
      call exchange2d_mpi(Fv_M,im,jm)
      call exchange2d_mpi(Fw_M,im,jm)

      if(mod(iext,ispadv).eq.0) call advave(tps)

      do j=2,jmm1
        do i=2,im
          uaf(i,j)=adx2d(i,j)+advua(i,j)
     $              -aru(i,j)*.25
     $                *(cor(i,j)*d(i,j)*(va(i,j+1)+va(i,j))
     $                 +cor(i-1,j)*d(i-1,j)*(va(i-1,j+1)+va(i-1,j)))
     $              +.25*grav*(dy(i,j)+dy(i-1,j))
     $                *(d(i,j)+d(i-1,j))
     $                *((1.-2.*alpha)
     $                   *(el(i,j)-el(i-1,j)
     &                    +.0005/grav
     &                        *((Fu_S(i,j)-Fu_S(i-1,j))
     &                         +(Fu_M(i,j)-Fu_M(i-1,j))))
     $                  +alpha*(elb(i,j)-elb(i-1,j)
     $                         +elf(i,j)-elf(i-1,j))
     $                  +e_atmos(i,j)-e_atmos(i-1,j))
     $              +drx2d(i,j)+aru(i,j)*(wusurf(i,j)-wubot(i,j))

        end do
      end do

!      if (my_task==master_task) then
!        print *, "dFu_S:", Fu_S(80,80)-Fu_S(79,80)
!        print *, "dFu_M:", Fu_M(80,80)-Fu_M(79,80)
!        print *, "dFu  :", Fu_S(80,80)-Fu_S(79,80)
!     &                    +Fu_M(80,80)-Fu_M(79,80)
!      end if

      do j=2,jmm1
        do i=2,im
          uaf(i,j)=((h(i,j)+elb(i,j)+h(i-1,j)+elb(i-1,j))
     $                *aru(i,j)*uab(i,j)
     $              -4.*dte*uaf(i,j))
     $             /((h(i,j)+elf(i,j)+h(i-1,j)+elf(i-1,j))
     $                 *aru(i,j))
!          uaf(i,j) = uaf(i,j) + 0.0005*(Fu_S(i,j)+Fu_M(i,j))*dte
        end do
      end do

      do j=2,jm
        do i=2,imm1
          vaf(i,j)=ady2d(i,j)+advva(i,j)
     $              +arv(i,j)*.25
     $                *(cor(i,j)*d(i,j)*(ua(i+1,j)+ua(i,j))
     $                 +cor(i,j-1)*d(i,j-1)*(ua(i+1,j-1)+ua(i,j-1)))
     $              +.25*grav*(dx(i,j)+dx(i,j-1))
     $                *(d(i,j)+d(i,j-1))
     $                *((1.-2.*alpha)
     &                   *(el(i,j)-el(i,j-1)
     &                    +.0005/grav
     &                        *((Fv_S(i,j)-Fv_S(i,j-1))
     &                         +(Fv_M(i,j)-Fv_M(i,j-1))))
     $                  +alpha*(elb(i,j)-elb(i,j-1)
     $                         +elf(i,j)-elf(i,j-1))
     $                  +e_atmos(i,j)-e_atmos(i,j-1))
     $              +dry2d(i,j)+arv(i,j)*(wvsurf(i,j)-wvbot(i,j))
        end do
      end do

!      if (my_task==master_task) then
!        print *, "dFv_S:", Fv_S(80,80)-Fv_S(79,80)
!        print *, "dFv_M:", Fv_M(80,80)-Fv_M(79,80)
!        print *, "dFv  :", Fv_S(80,80)-Fv_S(79,80)
!     &                    +Fv_M(80,80)-Fv_M(79,80)
!      end if

      do j=2,jm
        do i=2,imm1
          vaf(i,j)=((h(i,j)+elb(i,j)+h(i,j-1)+elb(i,j-1))
     $                *vab(i,j)*arv(i,j)
     $              -4.*dte*vaf(i,j))
     $             /((h(i,j)+elf(i,j)+h(i,j-1)+elf(i,j-1))
     $                 *arv(i,j))
!          vaf(i,j) = vaf(i,j) + 0.0005*(Fv_S(i,j)+Fv_M(i,j))*dte
        end do
      end do

      call bcond(2)

      call exchange2d_mpi(uaf,im,jm)
      call exchange2d_mpi(vaf,im,jm)

      if(iext.eq.(isplit-2))then
        do j=1,jm
          do i=1,im
            etf(i,j)=.25*smoth*elf(i,j)
          end do
        end do

      else if(iext.eq.(isplit-1)) then

        do j=1,jm
          do i=1,im
            etf(i,j)=etf(i,j)+.5*(1.-.5*smoth)*elf(i,j)
          end do
        end do

      else if(iext.eq.isplit) then

        do j=1,jm
          do i=1,im
            etf(i,j)=(etf(i,j)+.5*elf(i,j))*fsm(i,j)
          end do
        end do

      end if

! apply filter to remove time split
      do j=1,jm
        do i=1,im
          ua(i,j)=ua(i,j)+.5*smoth*(uab(i,j)-2.*ua(i,j)+uaf(i,j))
          va(i,j)=va(i,j)+.5*smoth*(vab(i,j)-2.*va(i,j)+vaf(i,j))
          el(i,j)=el(i,j)+.5*smoth*(elb(i,j)-2.*el(i,j)+elf(i,j))
          elb(i,j)=el(i,j)
          el(i,j)=elf(i,j)
          d(i,j)=h(i,j)+el(i,j)
          uab(i,j)=ua(i,j)
          ua(i,j)=uaf(i,j)
          vab(i,j)=va(i,j)
          va(i,j)=vaf(i,j)
        end do
      end do

      if(iext.ne.isplit) then
        do j=1,jm
          do i=1,im
            egf(i,j)=egf(i,j)+el(i,j)*ispi
          end do
        end do
        do j=1,jm
          do i=2,im
            utf(i,j)=utf(i,j)+ua(i,j)*(d(i,j)+d(i-1,j))*isp2i
          end do
        end do
        do j=2,jm
          do i=1,im
            vtf(i,j)=vtf(i,j)+va(i,j)*(d(i,j)+d(i,j-1))*isp2i
          end do
        end do
       end if

      return
      end

!_______________________________________________________________________
      subroutine mode_internal
! calculate the internal (3-D) mode
      implicit none
      include 'pom.h'
      integer i,j,k
      real(kind=rk) dxr,dxl,dyt,dyb

      if((iint.ne.1.or.time0.ne.0.).and.mode.ne.2) then

! adjust u(z) and v(z) such that depth average of (u,v) = (ua,va)
        do j=1,jm
          do i=1,im
            tps(i,j)=0.
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=1,im
              tps(i,j)=tps(i,j)+u(i,j,k)*dz(k)
            end do
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=2,im
              u(i,j,k)=(u(i,j,k)-tps(i,j))+
     $                 (utb(i,j)+utf(i,j))/(dt(i,j)+dt(i-1,j))
            end do
          end do
        end do

        do j=1,jm
          do i=1,im
            tps(i,j)=0.
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=1,im
              tps(i,j)=tps(i,j)+v(i,j,k)*dz(k)
            end do
          end do
        end do

        do k=1,kbm1
          do j=2,jm
            do i=1,im
              v(i,j,k)=(v(i,j,k)-tps(i,j))+
     $                 (vtb(i,j)+vtf(i,j))/(dt(i,j)+dt(i,j-1))
            end do
          end do
        end do

!eda: do drifter assimilation
!eda: this was the place where Lin et al. assimilate drifters
!eda: /home/xil/OIpsLag/gomc27_test87d_hcast2me_pseudo1.f
!     IF(MOD(IINT,16).EQ.0) THEN   ! 16 = 3.*3600./dti, every 3 hours
!--      IF(iint.eq.1 .or. MOD(IINT,16).EQ.0) THEN
!--      IF(MOD(IINT,IASSIM).EQ.0) THEN
!        call assimdrf_OIpsLag(time, itime1, mins, sec,
!    1     IM, JM, KB, u, v, Nx, Ny, beta, alon, alat, zz, D,
!    2     igs, ige, jgs, jge, ndrfmax,
!    3     ub, vb, dz, DrfDir)
!     endif

! calculate w from u, v, dt (h+et), etf and etb
        call vertvl(a,c)

        call bcond(5)

        call exchange3d_mpi(w,im,jm,kb)

! set uf and vf to zero
        do k=1,kb
          do j=1,jm
            do i=1,im
              uf(i,j,k)=0.
              vf(i,j,k)=0.
            end do
          end do
        end do

! calculate q2f and q2lf using uf, vf, a and c as temporary variables
        call advq(q2b,q2,uf,a,c)
        call advq(q2lb,q2l,vf,a,c)
        call profq(a,c,tps,dtef)

        where(q2l.lt..5*small) q2l = .5*small
        where(q2lb.lt..5*small) q2lb = .5*small
        call bcond(6)


        call exchange3d_mpi(uf(:,:,2:kbm1),im,jm,kbm2)
        call exchange3d_mpi(vf(:,:,2:kbm1),im,jm,kbm2)

        do k=1,kb
          do j=1,jm
            do i=1,im
              q2(i,j,k)=q2(i,j,k)
     $                   +.5*smoth*(uf(i,j,k)+q2b(i,j,k)
     $                                -2.*q2(i,j,k))
              q2l(i,j,k)=q2l(i,j,k)
     $                   +.5*smoth*(vf(i,j,k)+q2lb(i,j,k)
     $                                -2.*q2l(i,j,k))
              q2b(i,j,k)=q2(i,j,k)
              q2(i,j,k)=uf(i,j,k)
              q2lb(i,j,k)=q2l(i,j,k)
              q2l(i,j,k)=vf(i,j,k)
            end do
          end do
        end do


! calculate tf and sf using uf, vf, a and c as temporary variables
        if( mode /= 4 .and. ( iint > 2 .or. nread_rst == 1 ) ) then
          if(nadv.eq.1) then
!            call advt1(tb,t,tclim,uf,a,c)
!            call advt1(sb,s,sclim,vf,a,c)
            call advt1(tb,t,tclim,uf,a,c,'T')
            call advt1(sb,s,sclim,vf,a,c,'S')
          else if(nadv.eq.2) then
!            call advt2(tb,tclim,uf,a,c)
!            call advt2(sb,sclim,vf,a,c)
            call advt2(tb,tclim,uf,a,c,'T')
            call advt2(sb,sclim,vf,a,c,'S')
          else
            error_status=1
            write(6,'(/''Error: invalid value for nadv'')')
          endif


          call proft(uf,wtsurf,tsurf,nbct,tps)
          call proft(vf,wssurf,ssurf,nbcs,tps)


          call bcond(4)
          if (t_lo > -999.) then
            where (uf<t_lo) uf = t_lo
          end if
          if (t_hi <  999.) then
            where (uf>t_hi) uf = t_hi
          end if


          call exchange3d_mpi(uf(:,:,1:kbm1),im,jm,kbm1)
          call exchange3d_mpi(vf(:,:,1:kbm1),im,jm,kbm1)

          do k=1,kb
            do j=1,jm
              do i=1,im
                t(i,j,k)=t(i,j,k)
     $                    +.5*smoth*(uf(i,j,k)+tb(i,j,k)
     $                                 -2.*t(i,j,k))
                s(i,j,k)=s(i,j,k)
     $                    +.5*smoth*(vf(i,j,k)+sb(i,j,k)
     $                                 -2.*s(i,j,k))
                tb(i,j,k)=t(i,j,k)
                t(i,j,k)=uf(i,j,k)
                sb(i,j,k)=s(i,j,k)
                s(i,j,k)=vf(i,j,k)
              end do
            end do
          end do

          call dens(s,t,rho)

        end if

! calculate uf and vf
        call advu
        call advv
        call profu
        call profv

        call bcond(3)

        call exchange3d_mpi(uf(:,:,1:kbm1),im,jm,kbm1)
        call exchange3d_mpi(vf(:,:,1:kbm1),im,jm,kbm1)

        do j=1,jm
          do i=1,im
            tps(i,j)=0.
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=1,im
              tps(i,j)=tps(i,j)
     $                  +(uf(i,j,k)+ub(i,j,k)-2.*u(i,j,k))*dz(k)
            end do
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=1,im
              u(i,j,k)=u(i,j,k)
     $                  +.5*smoth*(uf(i,j,k)+ub(i,j,k)
     $                               -2.*u(i,j,k)-tps(i,j))
            end do
          end do
        end do

        do j=1,jm
          do i=1,im
            tps(i,j)=0.
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=1,im
              tps(i,j)=tps(i,j)
     $                  +(vf(i,j,k)+vb(i,j,k)-2.*v(i,j,k))*dz(k)
            end do
          end do
        end do

        do k=1,kbm1
          do j=1,jm
            do i=1,im
              v(i,j,k)=v(i,j,k)
     $                  +.5*smoth*(vf(i,j,k)+vb(i,j,k)
     $                               -2.*v(i,j,k)-tps(i,j))
            end do
          end do
        end do

        do k=1,kb
          do j=1,jm
            do i=1,im
              ub(i,j,k)=u(i,j,k)
              u(i,j,k)=uf(i,j,k)
              vb(i,j,k)=v(i,j,k)
              v(i,j,k)=vf(i,j,k)
            end do
          end do
        end do

      end if

      do j=1,jm
        do i=1,im
          egb(i,j)=egf(i,j)
          etb(i,j)=et(i,j)
          et(i,j)=etf(i,j)
          dt(i,j)=h(i,j)+et(i,j)
          utb(i,j)=utf(i,j)
          vtb(i,j)=vtf(i,j)
          vfluxb(i,j)=vfluxf(i,j)
        end do
      end do

! calculate real w as wr
      do k=1,kb
        do j=1,jm
          do i=1,im
            wr(i,j,k)=0.
          end do
        end do
      end do

      do k=1,kbm1
        do j=1,jm
          do i=1,im
            tps(i,j)=zz(k)*dt(i,j) + et(i,j)
          end do
        end do
        do j=2,jmm1
          do i=2,imm1
            dxr=2.0/(dx(i+1,j)+dx(i,j))
            dxl=2.0/(dx(i,j)+dx(i-1,j))
            dyt=2.0/(dy(i,j+1)+dy(i,j))
            dyb=2.0/(dy(i,j)+dy(i,j-1))
            wr(i,j,k)=0.5*(w(i,j,k)+w(i,j,k+1))+0.5*
     $                (u(i+1,j,k)*(tps(i+1,j)-tps(i,j))*dxr+
     $                 u(i,j,k)*(tps(i,j)-tps(i-1,j))*dxl+
     $                 v(i,j+1,k)*(tps(i,j+1)-tps(i,j))*dyt+
     $                 v(i,j,k)*(tps(i,j)-tps(i,j-1))*dyb)
     $                +(1.0+zz(k))*(etf(i,j)-etb(i,j))/dti2
          end do
        end do
      end do

      call exchange3d_mpi(wr(:,:,1:kbm1),im,jm,kbm1)

      do k=1,kb
        do i=1,im
          if(n_south.eq.-1) wr(i,1,k)=wr(i,2,k)
          if(n_north.eq.-1) wr(i,jm,k)=wr(i,jmm1,k)
        end do
      end do
      do k=1,kb
        do j=1,jm
          if(n_west.eq.-1) wr(1,j,k)=wr(2,j,k)
          if(n_east.eq.-1) wr(im,j,k)=wr(imm1,j,k)
        end do
      end do

      do k=1,kbm1
        do j=1,jm
          do i=1,im
            wr(i,j,k)=fsm(i,j)*wr(i,j,k)
          end do
        end do
      end do

      return
      end

!_______________________________________________________________________
      subroutine print_section
! print output
      implicit none
      include 'pom.h'
      real(kind=rk) area_tot,vol_tot,d_area,d_vol
      real(kind=rk) elev_ave, temp_ave, salt_ave
      integer i,j,k

      if(mod(iint,iprint).eq.0) then

! print time
        if(my_task.eq.master_task) write(6,'(/
     $    ''**********************************************************''
     $    /''time ='',f9.4,'', iint ='',i8,'', iext ='',i8,
     $    '', iprint ='',i8)') time,iint,iext,iprint

! check for errors
        call   sum0i_mpi(error_status,master_task)
        call bcast0i_mpi(error_status,master_task)
        if(error_status.ne.0) then
          if(my_task.eq.master_task) write(*,'(/a)')
     $                                       'POM terminated with error'
          call finalize_mpi
          stop
        end if

! local averages
        vol_tot  = 0.
        area_tot = 0.
        temp_ave = 0.
        salt_ave = 0.
        elev_ave = 0.

        do k=1,kbm1
           do j=1,jm
              do i=1,im
                 d_area   = dx(i,j) * dy(i,j)
                 d_vol    = d_area * dt(i,j) * dz(k) * fsm(i,j)
                 vol_tot  = vol_tot + d_vol
                 temp_ave = temp_ave + tb(i,j,k)*d_vol
                 salt_ave = salt_ave + sb(i,j,k)*d_vol
              end do
           end do
        end do

        do j=1,jm
          do i=1,im
             d_area = dx(i,j) * dy(i,j)
             area_tot = area_tot + d_area
             elev_ave = elev_ave + et(i,j) * d_area
          end do
        end do


        call sum0d_mpi( temp_ave, master_task )
        call sum0d_mpi( salt_ave, master_task )
        call sum0d_mpi( elev_ave, master_task )
        call sum0d_mpi(  vol_tot, master_task )
        call sum0d_mpi( area_tot, master_task )

! print averages
        if(my_task.eq.master_task) then

          temp_ave = temp_ave / vol_tot
          salt_ave = salt_ave / vol_tot
          elev_ave = elev_ave / area_tot
          write(*,'(a,e15.8,2(a,f11.8),a)')
     $       "mean ; et = ",elev_ave," m, tb = ",
     $       temp_ave + tbias," deg, sb = ",
     $       salt_ave + sbias," psu"

        end if

      end if

      return
      end

!_______________________________________________________________________
      subroutine check_velocity
! check if velocity condition is violated
      implicit none
      include 'pom.h'
      real(kind=rk) vamax
      integer i,j
      integer imax,jmax

      vamax = 0.

      do j=1,jm
        do i=1,im
          if(abs(vaf(i,j)).ge.vamax) then
            vamax=abs(vaf(i,j))
            imax=i
            jmax=j
          end if
        end do
      end do

      if(vamax.gt.vmaxl) then
        if (error_status.eq.0) write(*,'(/
     $    ''Error: velocity condition violated @ processor '',i3,/
     $    ''time ='',f9.4,
     $    '', iint ='',i8,'', iext ='',i8,'', iprint ='',i8,/
     $    ''vamax ='',e12.3,''   imax,jmax ='',2i5)')
     $    my_task,time,iint,iext,iprint,vamax,imax,jmax
        error_status=1
      end if

      return
      end

!_______________________________________________________________________
      subroutine store_mean

      implicit none
      include 'pom.h'

      uab_mean    = uab_mean    + uab
      vab_mean    = vab_mean    + vab
      elb_mean    = elb_mean    + elb
      wusurf_mean = wusurf_mean + wusurf
      wvsurf_mean = wvsurf_mean + wvsurf
      wtsurf_mean = wtsurf_mean + wtsurf
      wssurf_mean = wssurf_mean + wssurf
      u(:,:,kb)   = wubot(:,:)        !fhx:20110318:store wvbot
      v(:,:,kb)   = wvbot(:,:)        !fhx:20110318:store wvbot
      u_mean      = u_mean      + u
      v_mean      = v_mean      + v
      w_mean      = w_mean      + w
      t_mean      = t_mean      + t
      s_mean      = s_mean      + s
      rho_mean    = rho_mean    + rho
      kh_mean     = kh_mean     + kh
      aam(:,:,kb) = cbc(:,:)          !lyo:20110315:botwavedrag:store cbc
      km_mean     = km_mean     + aam !lyo:20110202:save aam inst. of km

      Fu_S_mean   = Fu_S_mean   + Fu_S
      Fv_S_mean   = Fv_S_mean   + Fv_S
      Fw_S_mean   = Fw_S_mean   + Fw_S
      Fu_M_mean   = Fu_M_mean   + Fu_M
      Fv_M_mean   = Fv_M_mean   + Fv_M
      Fw_M_mean   = Fw_M_mean   + Fw_M

      num = num + 1

      return
      end
!_______________________________________________________________________
      subroutine store_surf_mean !fhx:20110131:add new subr. for surf mean

      implicit none
      include 'pom.h'

      usrf_mean    = usrf_mean    + u(:,:,1)
      vsrf_mean    = vsrf_mean    + v(:,:,1)
      elsrf_mean    = elsrf_mean    + elb
      uwsrf_mean = uwsrf_mean + uwsrf
      vwsrf_mean = vwsrf_mean + vwsrf

      nums = nums + 1

      return
      end
!_______________________________________________________________________
!      subroutine write_output( d_in )
!
!      use module_time
!
!      implicit none
!      include 'pom.h'
!
!      type(date), intent(in) :: d_in
!
!      integer i,j,k
!      real(kind=rk) u_tmp, v_tmp
!
!      if(netcdf_file.ne.'nonetcdf' .and. mod(iint,iprint).eq.0) then
!
!
!         uab_mean    = uab_mean    / real ( num )
!         vab_mean    = vab_mean    / real ( num )
!         elb_mean    = elb_mean    / real ( num )
!         wusurf_mean = wusurf_mean / real ( num )
!         wvsurf_mean = wvsurf_mean / real ( num )
!         wtsurf_mean = wtsurf_mean / real ( num )
!         wssurf_mean = wssurf_mean / real ( num )
!         u_mean      = u_mean      / real ( num )
!         v_mean      = v_mean      / real ( num )
!         w_mean      = w_mean      / real ( num )
!         t_mean      = t_mean      / real ( num )
!         s_mean      = s_mean      / real ( num )
!         rho_mean    = rho_mean    / real ( num )
!         kh_mean     = kh_mean     / real ( num )
!         km_mean     = km_mean     / real ( num )
!
!
!
!!         if ( my_task == 41 )
!!     $        print*, im/2,jm/2,rot(im/2,jm/2),
!!     $        uab_mean(im/2,jm/2),vab_mean(im/2,jm/2)
!!         do j = 1, jm
!!            do i = 1, im
!!               u_tmp = uab_mean(i,j)
!!               v_tmp = vab_mean(i,j)
!!               uab_mean(i,j)
!!     $              = u_tmp * cos( rot(i,j) * deg2rad )
!!     $              - v_tmp * sin( rot(i,j) * deg2rad )
!!               vab_mean(i,j)
!!     $              = u_tmp * sin( rot(i,j) * deg2rad )
!!     $              + v_tmp * cos( rot(i,j) * deg2rad )
!!            enddo
!!         enddo
!!         if ( my_task == 41 )
!!     $        print*, im/2,jm/2,
!!     $        cos(rot(im/2,jm/2)*deg2rad),
!!     $        uab_mean(im/2,jm/2),vab_mean(im/2,jm/2)
!
!
!!         do j = 1, jm
!!            do i = 1, im
!!               u_tmp = wusurf_mean(i,j)
!!               v_tmp = wvsurf_mean(i,j)
!!               wusurf_mean(i,j)
!!     $              = u_tmp * cos( rot(i,j) * deg2rad )
!!     $              - v_tmp * sin( rot(i,j) * deg2rad )
!!               wvsurf_mean(i,j)
!!     $              = u_tmp * sin( rot(i,j) * deg2rad )
!!     $              + v_tmp * cos( rot(i,j) * deg2rad )
!!            enddo
!!         enddo
!!         do k=1,kbm1
!!            do j = 1, jm
!!               do i = 1, im
!!                  u_tmp = u_mean(i,j,k)
!!                  v_tmp = v_mean(i,j,k)
!!                  u_mean(i,j,k)
!!     $                 = u_tmp * cos( rot(i,j) * deg2rad )
!!     $                 - v_tmp * sin( rot(i,j) * deg2rad )
!!                  v_mean(i,j,k)
!!     $                 = u_tmp * sin( rot(i,j) * deg2rad )
!!     $                 + v_tmp * cos( rot(i,j) * deg2rad )
!!               enddo
!!            enddo
!!         enddo
!
!
!         write( filename, '("out/",2a,".nc")' )
!     $        trim( netcdf_file ), date2str( d_in )
!
!         call write_output_pnetcdf( filename )
!
!         uab_mean    = 0.0
!         vab_mean    = 0.0
!         elb_mean    = 0.0
!         wusurf_mean = 0.0
!         wvsurf_mean = 0.0
!         wtsurf_mean = 0.0
!         wssurf_mean = 0.0
!         u_mean      = 0.0
!         v_mean      = 0.0
!         w_mean      = 0.0
!         t_mean      = 0.0
!         s_mean      = 0.0
!         rho_mean    = 0.0
!         kh_mean     = 0.0
!         km_mean     = 0.0
!
!         num = 0
!
!      endif
!
!      return
!      end
!
!_______________________________________________________________________
      subroutine check_nan

      implicit none

      include 'pom.h'

      call detect_nan( u, "u" )
      call detect_nan( v, "v" )
      call detect_nan( t, "t" )
      call detect_nan( s, "s" )

      return
      end

!_______________________________________________________________________
      subroutine detect_nan( var, varname )

      implicit none
      include 'pom.h'

      integer i, j, k, num_nan
      real(kind=rk), intent(in) :: var(im,jm,kb)
      character(len=*),intent(in)  :: varname
!      logical isnanf

      num_nan = 0

      do i=1,im
         do j=1,jm
            do k=1,kb
               if ( isnan(var(i,j,k)) ) then
                  print'(2a,3i4,2f12.4)',
     $                 "detect nan : ",varname,
     $                 i_global(i),j_global(j),k,
     $                 var(i,j,k),h(i,j)
                  if ( k .eq. 1 ) num_nan = num_nan + 1
               endif
            enddo
         enddo
      enddo

      if ( num_nan .ne. 0 ) then
         print'(2a,2(a,i6))',
     $        " detect_nan : ", varname,
     $        "j_global(1) = ", j_global(1),
     $        ",   num_nan = ", num_nan
!         call finalize_mpi
         stop
      endif

      return
      end
!_______________________________________________________________________
!fhx:tide:debug
      subroutine check_nan_2d

      implicit none

      include 'pom.h'

      call detect_nan_2d( uaf, "uaf" )
      call detect_nan_2d( vaf, "vaf" )
      call detect_nan_2d( elf, "elf" )


      return
      end
!_______________________________________________________________________
!fhx:tide;debug
      subroutine detect_nan_2d( var, varname )

      implicit none
      include 'pom.h'

      integer i, j, num_nan
      real(kind=rk), intent(in) :: var(im,jm)
      character(len=*),intent(in)  :: varname
!      logical isnanf

      num_nan = 0

      do i=1,im
         do j=1,jm
               if ( isnan(var(i,j)) ) then
                  print'(2a,2i4,3f12.4)',
     $                 "detect nan : ",varname,
     $                 i_global(i),j_global(j),
     $                 var(i,j),h(i,j),time
                       num_nan = num_nan + 1
               endif

         enddo
      enddo

      if ( num_nan .ne. 0 ) then
         print'(2a,2(a,i6))',
     $        " detect_nan : ", varname,
     $        "j_global(1) = ", j_global(1),
     $        ",   num_nan = ", num_nan
!         call finalize_mpi
         stop
      endif

      return
      end
!_______________________________________________________________________

      subroutine pgscheme(npg)

        implicit none

        integer, intent(in) :: npg

        select case (npg)
          case (1)
            call baropg
          case (2)
            call baropg_mcc
          case (3)
            call baropg_lin
          case (4)
            call baropg_song_std
          case (5)
            call baropg_shch
          case default
            call baropg_mcc
        end select

      end subroutine

      subroutine sungrav(lat,lon,jd,time_in_day,time_in_sec
     &                  ,rot,Fu,Fv,Fw)

        implicit none
!
        include 'realkind'

        integer      , intent(in)  :: time_in_sec
        real(kind=rk), intent(in)  :: lat, lon, jd, time_in_day
        real(kind=rk), intent(out) :: rot, Fu, Fv, Fw

        real(kind=rk) degrad, eclips, raddeg, pi, alat, alon

        parameter(pi=3.1415927,degrad=pi/180.,raddeg=180./pi,
     $            eclips=23.439*degrad)

        real(kind=rk) Alt, app_lon, Az
     &              , c, DEC, dist, ecc
     &              , Fx, Fy, gmst, gmst0
     &              , h, mean_anom, mean_lon
     &              , obliq, RA, radius, sun_grav
     &              , t, true_anom, true_lon
     &              , w
!
! ---   lat,lon - in degrees!
!
        alat = lat*DEGRAD
        alon = lon*DEGRAD

        t = ( jd + time_in_day - 2451545. )/36525.

!
! --- geometric mean longitude
!
        mean_lon = 280.46646 + t*(36000.76938 + 0.0003032*t)
        mean_lon = modulo( mean_lon, 360. )
!
! --- mean anomaly
!
        mean_anom = 357.52911 + t*(35999.05029 + 0.0001537*t)
        mean_anom = modulo( mean_anom, 360. )
!
! --- Earth's orbit eccentricity
!
        ecc = 0.01678634 + t*(0.000042037 + 0.0000001267*t)
!
! --- Sun's eq. of the center
!
        c = (1.914602 - t*(0.004817+0.000014*t)*sin(  mean_anom*DEGRAD)
     &    + (0.019993 - t* 0.000101)           *sin(2*mean_anom*DEGRAD)
     &    +  0.000289                          *sin(3*mean_anom*DEGRAD))
!
! --- Sun's true longitude and anomaly
!
        true_lon  = mean_lon  + c
        true_anom = mean_anom + c
!
! --- Sun-Earth distance
!
        radius = ( 1.000001018*(1.-ecc*ecc) )
     &         / ( 1. + ecc*cos(true_anom*DEGRAD) )
        dist = radius*149598000.
!
! --- Apparent longitude
!
        w = 125.04 - 1934.136*t
        app_lon = true_lon - 0.00569 - 0.00478*sin(w*DEGRAD)
!
! --- Obliquity of the ecliptic
!
        obliq = 23. + 26./60. + 21.448/3600.
     &        - t*(46.8150/3600.-t*(0.00059/3600.+0.001813/3600.*t))
!
! --- Correction for apparent position of the Sun
!
        obliq = obliq + 0.00256*cos(w*DEGRAD)
!
! --- The Sun's right ascention
!
        RA = atan2( cos(obliq*DEGRAD)*sin(app_lon*DEGRAD)
     &            , cos(app_lon*DEGRAD) )
        RA = modulo( RA*RADDEG, 360. )
!
! --- Sun declination
!
        DEC = asin( sin(obliq*DEGRAD)*sin(app_lon*DEGRAD) )
!
! --- Convert to horizontal coordinates
!
        t = ( jd - 2451545. )/36525.
        gmst0 = ( 24110.5484 + t*(8640184.812866
     &                           +t*( 0.093104 + 0.0000062*t)) )/3600.
        gmst0 = modulo( gmst0, 24. )

        gmst = gmst0 + (time_in_sec*1.00273790925)/3600.
        gmst = modulo( gmst, 24. )

        h = (gmst*15. + lon - RA)*DEGRAD
        Az = atan2( -cos(DEC)*sin(h), sin(DEC)*cos(alat)
     &                               -cos(DEC)*sin(alat)*cos(h) )
        Alt = asin( sin(DEC)*sin(alat) + cos(alat)*cos(DEC)*cos(h) )

!
! --- Calculate Sun's gravitatinal accelleration
!
        sun_grav = 6.6740831e-11 * 1.989e30 / (dist*1.e3)
!        sun_grav = 1.989e30 / 5.9722e24 * (6371. / dist)**3
!        sun_grav = sun_grav * 6.6740831e-11*1.989e30/(dist*1.e3)**2

        Fx = sun_grav*sin(Az)*cos(Alt)
     &      *(dist/dist-1.-cos(Az)*cos(Alt)*6371./dist)
        Fy = sun_grav*cos(Az)*cos(Alt)
     &      *(dist/dist-1.-sin(Az)*cos(Alt)*6371./dist)
        Fw = sun_grav*sin(Alt)
     &      *(dist/dist-1.) ! zero

        Fu = Fx*cos(rot) - Fy*sin(rot)
        Fv = Fx*sin(rot) - Fy*cos(rot)

        return
      end

      subroutine moongrav(lat,lon,jd,L0,L1,sigma_l,sigma_r,sigma_b
     &                   ,time_in_day,time_in_sec,rot,Fu,Fv,Fw)

        implicit none
!
        include 'realkind'

        integer      , intent(in)  :: time_in_sec
        real(kind=rk), intent(in)  :: lat, lon, time_in_day
        real(kind=rk), intent(out) :: rot, Fu, Fv, Fw

        real(kind=rk) degrad, eclips, raddeg, pi, alat, alon

        parameter(pi=3.1415927,degrad=pi/180.,raddeg=180./pi,
     $            eclips=23.439*degrad)

        real(kind=rk) Alt, app_lon, Az
     &              , DEC, dist, e
     &              , Fx, Fy, gmst, gmst0
     &              , h, jd, L0, L1
     &              , moon_grav, obliq, obliqD, omega, RA
     &              , sigma_b, sigma_l, sigma_r, t
     &              , true_lat, true_lon
!
! ---   lat,lon - in degrees!
!
        alat = lat*DEGRAD
        alon = lon*DEGRAD

        t = (jd + time_in_day -2451545.0)/36525;
        e = 1- 0.002516*t - 0.0000074*t*t
!
! --- geometric coordinates
!
        true_lon  = modulo( L1*RADDEG, 360. ) + sigma_l/1000000.
        true_lat  = sigma_b/1000000.
        dist = 385000.56 + sigma_r/1000.
!
! --- Apparent longitude
!
        app_lon = true_lon + 0.004610
!
! --- Obliquity of the ecliptic
!
        omega = (125.04452 - t*(1934.13261
     &                      + t*(0.00220708 + t/450000.)) )*DEGRAD
        obliq  = 23. + 26./60. + 21.448/3600.
     &         - t*(46.8150/3600.-t*(0.00059/3600.+0.001813/3600.*t))
        obliqD = 9.2/3600.*cos(omega) + 0.57/3600.*cos(2.*L0)
     &         + 0.1/3600.*cos(2.*L1) - 0.09/3600.*cos(2.*omega)
!
! --- Correction for apparent position of the Moon
!
        obliq = obliq + obliqD
!
! --- The Moon's right ascention
!
        RA = (atan2( sin(true_lon*DEGRAD)*cos(obliq*DEGRAD)
     &              -tan(true_lat*DEGRAD)*sin(obliq*DEGRAD)
     &             , cos(true_lon*DEGRAD) )*RADDEG) / 15.
!
! --- Moon declination
!
        DEC = asin( sin(true_lat*DEGRAD)*cos(obliq*DEGRAD)
     &             +cos(true_lat*DEGRAD)*sin(obliq*DEGRAD)
     &             *sin(true_lon*DEGRAD) )*RADDEG
!
! --- Convert to horizontal coordinates
!
        t = ( jd - 2451545. )/36525.
        gmst0 = ( 24110.5484 + t*(8640184.812866
     &                           +t*( 0.093104 + 0.0000062*t)) )/3600.
        gmst0 = modulo( gmst0, 24. )

        gmst = gmst0 + (time_in_sec*1.00273790925)/3600.
        gmst = modulo( gmst, 24. )

        h = (gmst*15. + lon - (RA*15.))*DEGRAD
        Az = atan2( -cos(DEC)*sin(h), sin(DEC)*cos(alat)
     &                               -cos(DEC)*sin(alat)*cos(h) )
        Alt = asin( sin(DEC)*sin(alat) + cos(alat)*cos(DEC)*cos(h) )

!
! --- Calculate Moons's gravitational accelleration
!
        moon_grav = 6.6740831e-11 * 7.3476e22 / (dist*1.e3)
!        moon_grav = 7.3476e22 / 5.9722e24 * (6371. / dist)**3
!        moon_grav = moon_grav * 6.6740831e-11*7.3476e22/(dist*1.e3)**2

        Fx = moon_grav*sin(Az)*cos(Alt)
     &      *(dist/dist-1.-cos(Az)*cos(Alt)*6371./dist)
        Fy = moon_grav*cos(Az)*cos(Alt)
     &      *(dist/dist-1.-sin(Az)*cos(Alt)*6371./dist)
        Fw = moon_grav*sin(Alt)
     &      *(dist/dist-1.) ! zero

        Fu = Fx*cos(rot) - Fy*sin(rot)
        Fv = Fx*sin(rot) - Fy*cos(rot)

        return
      end

      subroutine update_vars(d_now
     &                      ,jd,time_in_day,time_in_sec
     &                      ,L0,L1,sigma_l,sigma_r,sigma_b)

        use module_time

        implicit none

        include 'realkind'

        type(date), intent(in) :: d_now
        real(kind=rk), intent(out) :: jd, time_in_day, L0, L1
     &                              , sigma_l, sigma_r, sigma_b
        integer, intent(out) :: time_in_sec

        real(kind=rk) degrad, raddeg, pi
        parameter(pi=3.1415927,degrad=pi/180.,raddeg=180./pi)

        real(kind=rk) A1,A2,A3,D0,e,F0,M0,M1,t
        integer day, month, year, t_off
!
! --- days from the epoch:
!
        year  = d_now%year
        month = d_now%month
        day   = d_now%day
        if ( month <= 2 ) then
          year  = year - 1
          month = month + 12
        end if

        time_in_day = d_now%hour/24.+d_now%min/1440.+d_now%sec/86400.
        time_in_sec = d_now%hour*3600 + d_now%min*60 + d_now%sec

        jd = floor(365.25*(year+4716.)) + floor(30.6001*(month+1))
     &     + day - 1524.5

        if ( jd < 2299160.5 ) then
          t_off = 0
        else
          t_off = 2 - floor(year/100.) + floor(floor(year/100.)/4.)
        end if

        jd = jd + t_off

        t = ( jd + time_in_day - 2451545. )/36525.
        e = 1. - t*(0.002516 - 0.0000074*t)
        L0 = ( 280.4665 + 36000.7698*t)*DEGRAD
        L1 = ( 218.3164477 + t*(481267.88123421
     &                      + t*(-0.0015786
     &                       + t*(1./538841. - t*65194000.))) )*DEGRAD
        D0 = ( 297.8501921 + t*(445267.1114034
     &                      + t*(-0.0018819
     &                       + t*(1./545868. - t/113065000.))) )*DEGRAD
        M0 = ( 357.5291092 + t*(35999.0502909
     &                      + t*(-0.0001536 + t/24490000.)) )*DEGRAD
        M1 = ( 134.9633964 + t*(477198.8675055
     &                      + t*(0.0087414
     &                       + t*(1./69699. - t/14712000.))) )*DEGRAD
        F0 = ( 93.2720950 + t*(483202.0175233
     &                     + t*(-0.0036539
     &                      + t*(-1./3526000. + t/863310000.))) )*DEGRAD
        A1 = ( 119.75 +    131.849*t )*DEGRAD
        A2 = (  53.09 + 479264.290*t )*DEGRAD
        A3 = ( 313.45 + 481266.484*t )*DEGRAD

        sigma_l = 6288774.*    sin(               M1      )
     &          + 1274027.*    sin(2.*D0      -   M1      )
     &          +  658314.*    sin(2.*D0                  )
     &          +  213618.*    sin(            2.*M1      )
     &          -  185116.*e*  sin(         M0            )
     &          -  114332.*    sin(                  2.*F0)
     &          +   58793.*    sin(2.*D0      -2.*M1      )
     &          +   57066.*e*  sin(2.*D0-   M0-   M1      )
     &          +   53322.*    sin(2.*D0      +   M1      )
     &          +   45758.*e*  sin(2.*D0-   M0            )
     &          -   40923.*e*  sin(         M0-   M1      )
     &          -   34720.*    sin(   D0                  )
     &          -   30383.*e*  sin(         M0+   M1      )
     &          +   15327.*    sin(2.*D0            -2.*F0)
     &          -   12528.*    sin(               M1+2.*F0)
     &          +   10980.*    sin(               M1-2.*F0)
     &          +   10675.*    sin(4.*D0      -   M1      )
     &          +   10034.*    sin(            3.*M1      )
     &          +    8548.*    sin(4.*D0      -2.*M1      )
     &          -    7888.*e*  sin(2.*D0+   M0-   M1      )
     &          -    6766.*e*  sin(2.*D0+   M0            )
     &          -    5163.*    sin(   D0      -   M1      )
     &          +    4987.*e*  sin(   D0+   M0            )
     &          +    4036.*e*  sin(2.*D0-   M0+   M1      )
     &          +    3994.*    sin(2.*D0      +2.*M1      )
     &          +    3861.*    sin(4.*D0                  )
     &          +    3665.*    sin(2.*D0      -3.*M1      )
     &          -    2689.*e*  sin(         M0-2.*M1      )
     &          -    2602.*    sin(2.*D0      -   M1+2.*F0)
     &          +    2390.*e*  sin(2.*D0-   M0-2.*M1      )
     &          -    2348.*    sin(   D0      +   M1      )
     &          +    2236.*e*e*sin(2.*D0-2.*M0            )
     &          -    2120.*e*  sin(         M0+2.*M1      )
     &          -    2069.*e*e*sin(      2.*M0            )
     &          +    2048.*e*e*sin(2.*D0-2.*M0-   M1      )
     &          -    1773.*    sin(2.*D0      +   M1-2.*F0)
     &          -    1595.*    sin(2.*D0            +2.*F0)
     &          +    1215.*e*  sin(4.*D0-   M0-   M1      )
     &          -    1110.*    sin(            2.*M1+2.*F0)
     &          -     892.*    sin(3.*D0      -   M1      )
     &          -     810.*e*  sin(2.*D0+   M0+   M1      )
     &          +     759.*e*  sin(4.*D0-   M0-2.*M1      )
     &          -     713.*e*e*sin(      2.*M0-   M1      )
     &          -     700.*e*e*sin(2.*D0+2.*M0-   M1      )
     &          +     691.*e*  sin(2.*D0+   M0-2.*M1      )
     &          +     596.*e*  sin(2.*D0-   M0      -2.*F0)
     &          +     549.*    sin(4.*D0      +   M1      )
     &          +     537.*    sin(            4.*M1      )
     &          +     520.*e*  sin(4.*D0-   M0            )
     &          -     487.*    sin(   D0      -2.*M1      )
     &          -     399.*e*  sin(2.*D0+   M0      -2.*F0)
     &          -     381.*    sin(            2.*M1-2.*F0)
     &          +     351.*e*  sin(   D0+   M0+   M1      )
     &          -     340.*    sin(3.*D0      -2.*M1      )
     &          +     330.*    sin(4.*D0      -3.*M1      )
     &          +     327.*e*  sin(2.*D0-   M0+2.*M1      )
     &          -     323.*e*e*sin(      2.*M0+   M1      )
     &          +     299.*e*  sin(   D0+   M0-   M1      )
     &          +     294.*    sin(2.*D0      +3.*M1      )

      sigma_r = -20905355.*    cos(               M1      )
     &          - 3699111.*    cos(2.*D0      -1.*M1      )
     &          - 2955968.*    cos(2.*D0                  )
     &          -  569925.*    cos(            2.*M1      )
     &          +   48888.*e*  cos(         M0            )
     &          -    3149.*    cos(                  2.*F0)
     &          +  246158.*    cos(2.*D0      -2.*M1      )
     &          -  152138.*e*  cos(2.*D0-   M0-   M1      )
     &          -  170733.*    cos(2.*D0      +   M1      )
     &          -  204586.*e*  cos(2.*D0-   M0            )
     &          -  129620.*e*  cos(         M0-   M1      )
     &          +  108743.*    cos(   D0                  )
     &          +  104755.*e*  cos(         M0+   M1      )
     &          +   10321.*    cos(2.*D0            -2.*F0)
     &          +   79661.*    cos(               M1-2.*F0)
     &          -   34782.*    cos(4.*D0      -   M1      )
     &          -   23210.*    cos(            3.*M1      )
     &          -   21636.*    cos(4.*D0      -2.*M1      )
     &          +   24208.*e*  cos(2.*D0+   M0-   M1      )
     &          +   30824.*e*  cos(2.*D0+   M0            )
     &          -    8379.*    cos(   D0      -   M1      )
     &          -   16675.*e*  cos(   D0+   M0            )
     &          -   12831.*e*  cos(2.*D0-   M0+   M1      )
     &          -   10445.*    cos(2.*D0      +2.*M1      )
     &          -   11650.*    cos(4.*D0                  )
     &          +   14403.*    cos(2.*D0      -3.*M1      )
     &          -    7003.*e*  cos(         M0-2.*M1      )
     &          +   10056.*e*  cos(2.*D0-   M0-2.*M1      )
     &          +    6322.*    cos(   D0      +   M1      )
     &          -    9884.*e*e*cos(2.*D0-2.*M0            )
     &          +    5751.*e*  cos(         M0+2.*M1      )
     &          -    4950.*e*e*cos(2.*D0-2.*M0-   M1      )
     &          +    4130.*    cos(2.*D0      +   M1-2.*F0)
     &          -    3958.*e*  cos(4.*D0-   M0-   M1      )
     &          +    3258.*    cos(3.*D0      -   M1      )
     &          +    2616.*e*  cos(2.*D0+   M0+   M1      )
     &          -    1897.*e*  cos(4.*D0-   M0-2.*M1      )
     &          -    2117.*e*e*cos(      2.*M0-   M1      )
     &          +    2354.*e*e*cos(2.*D0+2.*M0-   M1      )
     &          -    1423.*    cos(4.*D0      +   M1      )
     &          -    1117.*    cos(            4.*M1      )
     &          -    1571.*e*  cos(4.*D0-   M0            )
     &          -    1739.*    cos(   D0      -2.*M1      )
     &          -    4421.*    cos(            2.*M1-2.*F0)
     &          +    1165.*e*e*cos(      2.*M0+   M1      )
     &          +    8752.*    cos(2.*D0      -   M1-2.*F0)

        sigma_b = 5128122.*    sin(                     F0)
     &          +  280602.*    sin(               M1+   F0)
     &          +  277693.*    sin(               M1-   F0)
     &          +  173237.*    sin(2.*D0            -   F0)
     &          +   55413.*    sin(2.*D0      -   M1+   F0)
     &          +   46271.*    sin(2.*D0      -   M1-   F0)
     &          +   32573.*    sin(2.*D0            +   F0)
     &          +   17198.*    sin(            2.*M1+   F0)
     &          +    9266.*    sin(2.*D0      +   M1-   F0)
     &          +    8822.*    sin(            2.*M1-   F0)
     &          +    8216.*e*  sin(2.*D0-   M0      -   F0)
     &          +    4324.*    sin(2.*D0      -2.*M1-   F0)
     &          +    4200.*    sin(2.*D0      +   M1+   F0)
     &          -    3359.*e*  sin(2.*D0+   M0      -   F0)
     &          +    2463.*e*  sin(2.*D0-   M0-   M1+   F0)
     &          +    2211.*e*  sin(2.*D0-   M0      +   F0)
     &          +    2065.*e*  sin(2.*D0-   M0-   M1-   F0)
     &          -    1870.*e*  sin(         M0-   M1-   F0)
     &          +    1828.*    sin(4.*D0      -   M1-   F0)
     &          -    1794.*e*  sin(         M0      +   F0)
     &          -    1749.*    sin(                  3.*F0)
     &          -    1565.*e*  sin(         M0-   M1+   F0)
     &          -    1491.*    sin(   D0            +   F0)
     &          -    1475.*e*  sin(         M0+   M1+   F0)
     &          -    1410.*e*  sin(         M0+   M1-   F0)
     &          -    1344.*e*  sin(         M0      -   F0)
     &          -    1335.*    sin(   D0            -   F0)
     &          +    1107.*    sin(            3.*M1+   F0)
     &          +    1021.*    sin(4.*D0            -   F0)
     &          +     833.*    sin(4.*D0      -   M1+   F0)
     &          +     777.*    sin(               M1-3.*F0)
     &          +     671.*    sin(4.*D0      -2.*M1+   F0)
     &          +     607.*    sin(2.*D0            -3.*F0)
     &          +     596.*    sin(2.*D0      +2.*M1-   F0)
     &          +     491.*e*  sin(2.*D0-   M0+   M1-   F0)
     &          -     451.*    sin(2.*D0      -2.*M1+   F0)
     &          +     439.*    sin(            3.*M1-   F0)
     &          +     422.*    sin(2.*D0      +2.*M1+   F0)
     &          +     421.*    sin(2.*D0      -3.*M1-   F0)
     &          -     366.*e*  sin(2.*D0+   M0-   M1+   F0)
     &          -     351.*e*  sin(2.*D0+   M0      +   F0)
     &          +     331.*    sin(4.*D0            +   F0)
     &          +     315.*e*  sin(2.*D0-   M0+   M1+   F0)
     &          +     302.*e*e*sin(2.*D0-2.*M0      -   F0)
     &          -     283.*    sin(               M1+3.*F0)
     &          -     229.*e*  sin(2.*D0+   M0+   M1-   F0)
     &          +     223.*e*  sin(   D0+   M0      -   F0)
     &          +     223.*e*  sin(   D0+   M0      +   F0)
     &          -     220.*e*  sin(         M0-2.*M1-   F0)
     &          -     220.*e*  sin(2.*D0+   M0-   M1-   F0)
     &          -     185.*    sin(   D0      +   M1+   F0)
     &          +     181.*e*  sin(2.*D0-   M0-2.*M1-   F0)
     &          -     177.*e*  sin(         M0+2.*M1+   F0)
     &          +     176.*    sin(4.*D0      -2.*M1-   F0)
     &          +     166.*e*  sin(4.*D0-   M0-   M1-   F0)
     &          -     164.*    sin(   D0      +   M1-   F0)
     &          +     132.*    sin(4.*D0      +   M1-   F0)
     &          -     119.*    sin(   D0      -   M1-   F0)
     &          +     115.*e*  sin(4.*D0-   M0      -   F0)
     &          +     107.*e*e*sin(2.*D0-2.*M0      +   F0)

        sigma_l = sigma_l + 3958.*sin(A1)
     &                    + 1962.*sin(L1-F0)
     &                    +  318.*sin(A2)

        sigma_b = sigma_b - 2235.*sin(L1)
     &                    +  382.*sin(A3)
     &                    +  175.*sin(A1-F0)
     &                    +  175.*sin(A1+F0)
     &                    +  127.*sin(L1-M1)
     &                    -  115.*sin(L1+M1)

      end
