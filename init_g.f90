!> This module contains the subroutines which set the initial value of the
!! fields and the distribution function.

module init_g
  implicit none

  public :: ginit
  public :: init_init_g, finish_init_g
  public :: width0
  public :: tstart
  public :: reset_init

  private

  ! knobs
  integer :: ginitopt_switch
  integer, parameter :: ginitopt_default = 1,  &
       ginitopt_noise = 2, ginitopt_restart_many = 3, &
       ginitopt_kpar = 4, ginitopt_nltest = 5, &
       ginitopt_kxtest = 6, ginitopt_rh = 7

  real :: width0, phiinit, imfac, refac, zf_init
  real :: den0, upar0, tpar0, tperp0
  real :: den1, upar1, tpar1, tperp1
  real :: den2, upar2, tpar2, tperp2
  real :: tstart, scale
  logical :: chop_side, left, even
  character(300), public :: restart_file
  character (len=150) :: restart_dir

  !>  This is used  in linear runs with flow shear  in order to track the
  !! evolution of a single Lagrangian mode.
  integer :: ikx_init

  logical :: debug = .false.
  logical :: initialized = .false.
  logical :: exist

contains

  subroutine init_init_g
    use stella_save, only: init_save, read_many
    use stella_layouts, only: init_stella_layouts
    use mp, only: proc0, broadcast
    implicit none
    integer :: ind_slash

    if (initialized) return
    initialized = .true.
    call init_stella_layouts

    if (proc0) call read_parameters

    ! prepend restart_dir to restart_file
    ! append trailing slash if not exists
    if(restart_dir(len_trim(restart_dir):) /= "/") &
         restart_dir=trim(restart_dir)//"/"
    !Determine if restart file contains "/" if so split on this point to give DIR//FILE
    !so restart files are created in DIR//restart_dir//FILE
    ind_slash=index(restart_file,"/",.True.)
    if (ind_slash.EQ.0) then !No slash present
       restart_file=trim(restart_dir)//trim(restart_file)
    else !Slash present
       restart_file=trim(restart_file(1:ind_slash))//trim(restart_dir)//trim(restart_file(ind_slash+1:))
    endif

    call broadcast (ginitopt_switch)
    call broadcast (width0)
    call broadcast (refac)
    call broadcast (imfac)
    call broadcast (den0)
    call broadcast (upar0)
    call broadcast (tpar0)
    call broadcast (tperp0)
    call broadcast (den1)
    call broadcast (upar1)
    call broadcast (tpar1)
    call broadcast (tperp1)
    call broadcast (den2)
    call broadcast (upar2)
    call broadcast (tpar2)
    call broadcast (tperp2)
    call broadcast (phiinit)
    call broadcast (zf_init)
    call broadcast (tstart)
    call broadcast (chop_side)
    call broadcast (even)
    call broadcast (left)
    call broadcast (restart_file)
    call broadcast (read_many)
    call broadcast (scale)

    call init_save (restart_file)

  end subroutine init_init_g

  subroutine ginit (restarted)

    use stella_save, only: init_tstart
    logical, intent (out) :: restarted
    integer :: istatus

    restarted = .false.
    select case (ginitopt_switch)
    case (ginitopt_default)
       call ginit_default
!     case (ginitopt_noise)
!        call ginit_noise
     case (ginitopt_kpar)
        call ginit_kpar
!     case (ginitopt_rh)
!        call ginit_rh
    case (ginitopt_restart_many)
       call ginit_restart_many 
       call init_tstart (tstart, istatus)
       restarted = .true.
       scale = 1.
!    case (ginitopt_nltest)
!       call ginit_nltest
!    case (ginitopt_kxtest)
!       call ginit_kxtest
    end select
    
  end subroutine ginit

  subroutine read_parameters
    use file_utils, only: input_unit, error_unit, run_name, input_unit_exist
    use text_options, only: text_option, get_option_value
    use stella_save, only: read_many

    implicit none

    type (text_option), dimension (7), parameter :: ginitopts = &
         (/ text_option('default', ginitopt_default), &
            text_option('noise', ginitopt_noise), &
            text_option('many', ginitopt_restart_many), &
            text_option('nltest', ginitopt_nltest), &
            text_option('kxtest', ginitopt_kxtest), &
            text_option('kpar', ginitopt_kpar), &
            text_option('rh', ginitopt_rh) &
            /)
    character(20) :: ginit_option
    namelist /init_g_knobs/ ginit_option, width0, phiinit, chop_side, &
         restart_file, restart_dir, read_many, left, scale, tstart, zf_init, &
         den0, upar0, tpar0, tperp0, imfac, refac, even, &
         den1, upar1, tpar1, tperp1, &
         den2, upar2, tpar2, tperp2, &
         ikx_init

    integer :: ierr, in_file

    tstart = 0.
    scale = 1.0
    ginit_option = "default"
    width0 = -3.5
    refac = 1.
    imfac = 0.
    den0 = 1.
    upar0 = 0.
    tpar0 = 0.
    tperp0 = 0.
    den1 = 0.
    upar1 = 0.
    tpar1 = 0.
    tperp1 = 0.
    den2 = 0.
    upar2 = 0.
    tpar2 = 0.
    tperp2 = 0.
    phiinit = 1.0
    zf_init = 1.0
    chop_side = .true.
    left = .true.
    even = .true.

    restart_file = trim(run_name)//".nc"
    restart_dir = "./"
    in_file = input_unit_exist ("init_g_knobs", exist)
!    if (exist) read (unit=input_unit("init_g_knobs"), nml=init_g_knobs)
    if (exist) read (unit=in_file,nml=init_g_knobs)

    ierr = error_unit()
    call get_option_value &
         (ginit_option, ginitopts, ginitopt_switch, &
         ierr, "ginit_option in ginit_knobs")
  end subroutine read_parameters

  subroutine ginit_default

    use species, only: spec
    use theta_grid, only: ntgrid, theta, bmag
    use kt_grids, only: naky, ntheta0, theta0, aky, reality
    use vpamu_grids, only: nvpa, vpa, mu, nmu
    use dist_fn_arrays, only: gvmu
    use stella_layouts, only: gvmu_lo, ig_idx, it_idx, ik_idx, is_idx

    implicit none

    complex, dimension (naky,ntheta0,-ntgrid:ntgrid) :: phi
    logical :: right
    integer :: ivmu
    integer :: ig, ik, it, is

    right = .not. left

    do ig = -ntgrid, ntgrid
       phi(:,:,ig) = exp(-((theta(ig)-theta0(:,:))/width0)**2)*cmplx(1.0,1.0)
    end do
    if (chop_side .and. left) phi(:,:,:-1) = 0.0
    if (chop_side .and. right) phi(:,:,1:) = 0.0
    
    if (reality) then
       phi(1,1,:) = 0.0

       if (naky > 1 .and. aky(1) < epsilon(0.0)) then
          phi(1,:,:) = 0.0
       end if

! not used:
! reality condition for k_theta = 0 component:
       do it = 1, ntheta0/2
          phi(1,it+(ntheta0+1)/2,:) = conjg(phi(1,(ntheta0+1)/2+1-it,:))
       enddo
    end if

    do ivmu = gvmu_lo%llim_proc, gvmu_lo%ulim_proc
       ig = ig_idx(gvmu_lo,ivmu)
       it = it_idx(gvmu_lo,ivmu)
       ik = ik_idx(gvmu_lo,ivmu)
       is = is_idx(gvmu_lo,ivmu)
!          gnew(:,it,:,ivmu) = spread(exp(-2.0*mu(imu)*bmag),2,naky)**phi(:,it,:) &
       gvmu(:,:,ivmu) = spread(exp(-2.0*mu*bmag(ig)),1,nvpa)*phi(ik,it,ig) &
!       gvmu(:,:,ivmu) = phi(ik,it,ig) &
            *spec(is)%z*phiinit*spread(exp(-vpa**2),2,nmu)
    end do

  end subroutine ginit_default

  ! initialize two kys and kx=0
!   subroutine ginit_nltest

!     use mp, only: proc0
!     use species, only: spec
!     use theta_grid, only: ntgrid, bmag
!     use kt_grids, only: naky, ntheta0
!     use vpamu_grids, only: nvgrid, vpa, mu
!     use dist_fn_arrays, only: gnew, gold
!     use stella_layouts, only: gxyz_lo, iv_idx, is_idx, imu_idx

!     implicit none

!     complex, dimension (-ntgrid:ntgrid,ntheta0,naky) :: phi
!     logical :: right
!     integer :: iglo
!     integer :: ig, ik, it, is, iv, imu

!     right = .not. left

!     if (naky < 4 .or. ntheta0 < 2) then
!        if (proc0) write (*,*) 'must have at least 2 kxs and 4 kys to use nltest init option. aborting.'
!        stop
!     end if

!     phi = 0.0
!     do ig = -ntgrid, ntgrid
!        phi(ig,2,2) = 1.0!exp(-((theta(ig)-theta0(2,2))/width0)**2)*cmplx(1.0,1.0)
!     end do
    
!     gnew = 0.0
!     do iglo = gxyz_lo%llim_proc, gxyz_lo%ulim_proc
!        iv = iv_idx(gxyz_lo,iglo)
!        is = is_idx(gxyz_lo,iglo)
!        imu = imu_idx(gxyz_lo,iglo)
!        it = 1
!        do ik = 2, 3
!           gnew(:,it,ik,iglo) = exp(-2.0*mu(imu)*bmag)*phi(:,it,ik) &
!                *spec(is)%z*phiinit*exp(-vpa(iv)**2)
!        end do
!     end do
!     gold = gnew

!   end subroutine ginit_nltest

!   subroutine ginit_kxtest

!     use constants, only: zi
!     use species, only: spec
!     use theta_grid, only: itor_over_b
!     use kt_grids, only: ntheta0, akx, naky
!     use vpamu_grids, only: nvgrid, energy, vpa
!     use dist_fn_arrays, only: gnew, gold
!     use stella_layouts, only: gxyz_lo, iv_idx, is_idx, imu_idx

!     implicit none

!     integer :: iglo
!     integer :: ik, it, is, imu, iv

!     do iglo = gxyz_lo%llim_proc, gxyz_lo%ulim_proc
!        iv = iv_idx(gxyz_lo,iglo)
!        is = is_idx(gxyz_lo,iglo)
!        imu = imu_idx(gxyz_lo,iglo)
!        do it = 1, ntheta0
!           do ik = 1, naky
!              gnew(:,it,ik,iglo) = exp(-zi*akx(it)*itor_over_B*vpa(iv)/spec(is)%zstm) &
!                   *exp(-energy(:,iv,imu))*spec(is)%z*phiinit
!           end do
!        end do
!     end do
!     gold = gnew

!   end subroutine ginit_kxtest

!   !> Initialise with only the kparallel = 0 mode.
  
!   subroutine single_initial_kx(phi)
!     use theta_grid, only: ntgrid 
!     use kt_grids, only: naky, ntheta0
!     use mp, only: mp_abort
!     implicit none
!     complex, dimension (-ntgrid:ntgrid,ntheta0,naky), intent(inout) :: phi
!     real :: a, b
!     integer :: ig, ik, it

!     if (ikx_init  < 2 .or. ikx_init > (ntheta0+1)/2) then
!       call mp_abort("The subroutine single_initial_kx should only be called when 1 < ikx_init < (ntheta0+1)/2")
!     end if

!     do it = 1, ntheta0
!       if (it .ne. ikx_init) then 
!          do ik = 1, naky
!             do ig = -ntgrid, ntgrid
!                a = 0.0
!                b = 0.0 
!                phi(ig,it,ik) = cmplx(a,b)
!              end do
!          end do
!        end if
!     end do
!   end subroutine single_initial_kx

  !> Initialise the distribution function with random noise. This is the default
  !! initialisation option. Each different mode is given a random amplitude
  !! between zero and one.

!   subroutine ginit_noise

!     use mp, only: proc0, broadcast
!     use species, only: spec
!     use theta_grid, only: ntgrid, bmag
!     use kt_grids, only: naky, ntheta0, aky, reality
!     use vpamu_grids, only: nvgrid, vpa, mu
!     use dist_fn_arrays, only: gnew, gold, kperp2
!     use stella_layouts, only: gxyz_lo, iv_idx, is_idx, imu_idx, proc_id
!     use mp, only: proc0, broadcast
!     use ran

!     implicit none

!     complex, dimension (-ntgrid:ntgrid,ntheta0,naky) :: phi
!     real :: a, b, kmin
!     integer :: iglo, ig, ik, it, imu, is, iv

!     if (proc0) then
!        ! keep old (it, ik) loop order to get old results exactly: 
!        kmin = min(minval(kperp2(:,1,2)),minval(kperp2(:,2,1)))
       
!        !Fill phi with random (complex) numbers between -0.5 and 0.5
!        do it = 1, ntheta0
!           do ik = 1, naky
!              do ig = -ntgrid, ntgrid
!                 a = ranf()-0.5
!                 b = ranf()-0.5
!                 ! don't populate high k's with large amplitudes
!                 if (it > 1 .or. ik > 1) phi(ig,it,ik) = cmplx(a,b)*kmin/sqrt(kperp2(ig,it,ik))
!              end do
!              if (chop_side) then
!                 if (left) then
!                    phi(:-1,it,ik) = 0.0
!                 else
!                    phi(1:,it,ik) = 0.0
!                 endif
!              end if
!           end do
!        end do

!        !Wipe out all but one kx if requested
!        if (ikx_init  > 0) call single_initial_kx(phi)
       
!        !Sort out the zonal/self-periodic modes
!        if (naky .ge. 1 .and. aky(1) < epsilon(0.0)) then
!           !Apply scaling factor
!           phi(:,:,1) = phi(:,:,1)*zf_init
          
!           !Set ky=kx=0.0 mode to zero in amplitude
!           phi(:,1,1) = 0.0
!        end if

!        !Apply reality condition (i.e. -kx mode is conjugate of +kx mode)
!        if (reality) then
!           do it = 1, ntheta0/2
!              phi(:,it+(ntheta0+1)/2,1) = conjg(phi(:,(ntheta0+1)/2+1-it,1))
!           enddo
!        end if

!     end if

!     do ig = -ntgrid, ntgrid
!        call broadcast (phi(ig,:,:))
!     end do

!     !Now set g using data in phi
!     do iglo = gxyz_lo%llim_proc, gxyz_lo%ulim_proc
!        iv = iv_idx(gxyz_lo,iglo)
!        is = is_idx(gxyz_lo,iglo)
!        imu = imu_idx(gxyz_lo,iglo)

!        do it = 1, ntheta0
!           gnew(:,it,:,iglo) = -spread(exp(-2.0*mu(imu)*bmag),2,naky)*phi(:,it,:) &
!                *spec(is)%z*phiinit*exp(-vpa(iv)**2)
!        end do
!     end do

!     gold = gnew
    
!   end subroutine ginit_noise

  subroutine ginit_kpar

!    use species, only: spec, has_electron_species
    use theta_grid, only: ntgrid, theta
    use kt_grids, only: naky, ntheta0, theta0
    use vpamu_grids, only: nvgrid, nmu
    use vpamu_grids, only: vpa, vperp2, anon
    use dist_fn_arrays, only: gvmu
    use stella_layouts, only: gvmu_lo, ik_idx, it_idx, ig_idx
    use constants, only: zi

    implicit none

    complex, dimension (naky,ntheta0,-ntgrid:ntgrid) :: phi, odd
    real, dimension (-ntgrid:ntgrid) :: dfac, ufac, tparfac, tperpfac
    integer :: ivmu
    integer :: ig, ik, it, imu, iv
    
    phi = 0.
    odd = 0.
    if (width0 > 0.) then
       do ig = -ntgrid, ntgrid
          phi(:,:,ig) = exp(-((theta(ig)-theta0(:,:))/width0)**2)*cmplx(refac, imfac)
       end do
    else
       do ig = -ntgrid, ntgrid
          phi(:,:,ig) = cmplx(refac, imfac)
       end do
    end if
    if (chop_side) then
       if (left) then
          phi(:,:,:-1) = 0.0
       else
          phi(:,:,1:) = 0.0
       end if
    end if
    
    odd = zi * phi
        
    dfac     = den0   + den1 * cos(theta) + den2 * cos(2.*theta) 
    ufac     = upar0  + upar1* sin(theta) + upar2* sin(2.*theta) 
    tparfac  = tpar0  + tpar1* cos(theta) + tpar2* cos(2.*theta) 
    tperpfac = tperp0 + tperp1*cos(theta) + tperp2*cos(2.*theta) 

! charge dependence keeps initial Phi from being too small
    do ivmu = gvmu_lo%llim_proc, gvmu_lo%ulim_proc
       ik = ik_idx(gvmu_lo,ivmu)
       it = it_idx(gvmu_lo,ivmu)
       ig = ig_idx(gvmu_lo,ivmu)
       do imu = 1, nmu
          do iv = -nvgrid, nvgrid
             gvmu(iv,imu,ivmu) = phiinit*anon(ig,iv,imu) &
                  * ( dfac(ig)*phi(ik,it,ig) &
                  + 2.0*vpa(iv)*ufac(ig)*odd(ik,it,ig) &
                  + (vpa(iv)**2-0.5)*tparfac(ig)*phi(ik,it,ig) &
                  + tperpfac(ig)*(vperp2(ig,imu)-1.)*phi(ik,it,ig) )
          end do
       end do
    end do
! FLAG -- should be uncommented, which means I need to fix flae
!    if (has_electron_species(spec)) then
!       call flae (gold, gnew)
!       gold = gold - gnew
!    end if   
!    gnew = gold

  end subroutine ginit_kpar

!   subroutine ginit_rh

!     use species, only: spec, has_electron_species
!     use theta_grid, only: ntgrid, bmag
!     use kt_grids, only: naky, ntheta0
!     use vpamu_grids, only: nvgrid, vpa, mu
!     use dist_fn_arrays, only: gnew, gold, kperp2
!     use stella_layouts, only: gxyz_lo, iv_idx, imu_idx, is_idx
!     use constants
!     use ran

!     implicit none

!     complex, dimension (-ntgrid:ntgrid,ntheta0,naky) :: phi
!     integer :: iglo
!     integer :: iv, it, imu, is
    
!     ! initialize g to be a Maxwellian with a constant density perturbation

!     phi(:,:,1) = phiinit

!     do iglo = gxyz_lo%llim_proc, gxyz_lo%ulim_proc
!        iv = iv_idx(gxyz_lo,iglo)
!        imu = imu_idx(gxyz_lo,iglo)
!        is = is_idx(gxyz_lo,iglo)

!        do it = 1, ntheta0
!           gnew(:,it,:,iglo) = spec(is)%z*0.5*exp(-vpa(iv)**2) &
!                * spread(exp(-2.0*mu(imu)*bmag),naky,2)*phi(:,it,:)*kperp2(:,it,:)
!        end do
!     end do

!     gold = gnew

!   end subroutine ginit_rh

  subroutine ginit_restart_many

    use dist_fn_arrays, only: gvmu
    use stella_save, only: stella_restore
    use mp, only: proc0
    use file_utils, only: error_unit
    use run_parameters, only: fphi, fapar
    
    implicit none

    integer :: istatus, ierr

    ! should really check if profile_variation=T here but need
    ! to move profile_variation to module that is accessible here
    call stella_restore (gvmu, scale, istatus, fphi, fapar)

    if (istatus /= 0) then
       ierr = error_unit()
       if (proc0) write(ierr,*) "Error reading file: ", trim(restart_file)
       gvmu = 0.
    end if

  end subroutine ginit_restart_many

  subroutine reset_init

    ginitopt_switch = ginitopt_restart_many

  end subroutine reset_init

!   subroutine flae (g, gavg)

!     use species, only: spec, electron_species 
!     use theta_grid, only: ntgrid, delthet, jacob
!     use kt_grids, only: aky, ntheta0
!     use vpamu_grids, only: nvgrid
!     use stella_layouts, only: gxyz_lo, is_idx
!     complex, dimension (-ntgrid:,:,:,gxyz_lo%llim_proc:), intent (in) :: g
!     complex, dimension (-ntgrid:,:,:,gxyz_lo%llim_proc:), intent (out) :: gavg

!     real :: wgt
!     integer :: iglo, it, ik
    
!     gavg = 0.
!     wgt = 1./sum(delthet*jacob)

!     do iglo = gxyz_lo%llim_proc, gxyz_lo%ulim_proc       
!        if (spec(is_idx(gxyz_lo, iglo))%type /= electron_species) cycle
!        ik = 1
!        if (aky(ik) > epsilon(0.)) cycle
!        do it = 1, ntheta0
!           gavg(:,it,ik,iglo) = sum(g(:,it,ik,iglo)*delthet*jacob)*wgt
!        end do
!     end do
    
!   end subroutine flae

  subroutine finish_init_g

    implicit none

    initialized = .false.

  end subroutine finish_init_g

end module init_g