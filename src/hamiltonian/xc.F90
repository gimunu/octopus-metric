!! Copyright (C) 2002-2006 M. Marques, A. Castro, A. Rubio, G. Bertsch
!!
!! This program is free software; you can redistribute it and/or modify
!! it under the terms of the GNU General Public License as published by
!! the Free Software Foundation; either version 2, or (at your option)
!! any later version.
!!
!! This program is distributed in the hope that it will be useful,
!! but WITHOUT ANY WARRANTY; without even the implied warranty of
!! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!! GNU General Public License for more details.
!!
!! You should have received a copy of the GNU General Public License
!! along with this program; if not, write to the Free Software
!! Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
!! 02110-1301, USA.
!!
!! $Id: xc.F90 15203 2016-03-19 13:15:05Z xavier $

#include "global.h"

module xc_oct_m
  use distributed_oct_m
  use comm_oct_m
  use cube_oct_m
  use cube_function_oct_m
  use derivatives_oct_m
  use global_oct_m
  use grid_oct_m
  use index_oct_m
  use io_oct_m
  use io_function_oct_m
  use lalg_basic_oct_m
  use lalg_adv_oct_m
  use libvdwxc_oct_m
  use mesh_oct_m
  use mesh_function_oct_m
  use messages_oct_m
  use mpi_oct_m
  use par_vec_oct_m
  use parser_oct_m
  use poisson_oct_m
  use profiling_oct_m
  use states_oct_m
  use states_dim_oct_m
  use symmetrizer_oct_m
  use unit_system_oct_m
  use varinfo_oct_m
  use XC_F90(lib_m)
  use xc_functl_oct_m

  implicit none

  private
  public ::             &
    xc_t,               &
    xc_init,            &
    xc_end,             &
    xc_write_info,      &
    xc_get_vxc,         &
    xc_get_vxc_cmplx,   &
    xc_get_fxc,         &
    xc_get_kxc,         &
    xc_is_orbital_dependent


  type xc_t
    integer :: family                   !< the families present
    integer :: kernel_family
    type(xc_functl_t) :: functional(2,2)    !< (FUNC_X,:) => exchange,    (FUNC_C,:) => correlation
                                        !< (:,1) => unpolarized, (:,2) => polarized

    type(xc_functl_t) :: kernel(2,2)
    FLOAT   :: kernel_lrc_alpha         !< long-range correction alpha parameter for kernel in solids

    FLOAT   :: exx_coef                 !< amount of EXX to add for the hybrids
    logical :: use_gi_ked               !< should we use the gauge-independent kinetic energy density?

    integer :: xc_density_correction
    logical :: xcd_optimize_cutoff
    FLOAT   :: xcd_ncutoff
    logical :: xcd_minimum
    logical :: xcd_normalize
    logical :: parallel
  end type xc_t

  FLOAT, parameter :: tiny      = CNST(1.0e-12)

  integer, parameter :: &
    LR_NONE = 0,        &
    LR_X    = 1

  integer, public, parameter :: &
    FUNC_X = 1,         &
    FUNC_C = 2

contains

  ! ---------------------------------------------------------
  subroutine xc_write_info(xcs, iunit)
    type(xc_t), intent(in) :: xcs
    integer,    intent(in) :: iunit

    integer :: ifunc

    PUSH_SUB(xc_write_info)

    write(message(1), '(a)') "Exchange-correlation:"
    call messages_info(1, iunit)

    do ifunc = FUNC_X, FUNC_C
      call xc_functl_write_info(xcs%functional(ifunc, 1), iunit)
    end do
    
    if(xcs%exx_coef /= M_ZERO) then
      write(message(1), '(1x)')
      write(message(2), '(a,f8.5)') "Exact exchange mixing = ", xcs%exx_coef
      call messages_info(2, iunit)
    end if

    POP_SUB(xc_write_info)
  end subroutine xc_write_info


  ! ---------------------------------------------------------
  subroutine xc_init(xcs, ndim, periodic_dim, nel, x_id, c_id, xk_id, ck_id, hartree_fock)
    type(xc_t), intent(out) :: xcs
    integer,    intent(in)  :: ndim
    integer,    intent(in)  :: periodic_dim
    FLOAT,      intent(in)  :: nel
    integer,    intent(in)  :: x_id
    integer,    intent(in)  :: c_id
    integer,    intent(in)  :: xk_id
    integer,    intent(in)  :: ck_id
    logical,    intent(in)  :: hartree_fock

    integer :: isp
    logical :: ll

    PUSH_SUB(xc_init)

    xcs%family = 0
    xcs%kernel_family = 0

    call parse()

    !we also need XC functionals that do not depend on the current
    !get both spin-polarized and unpolarized
    do isp = 1, 2

      call xc_functl_init_functl(xcs%functional(FUNC_X, isp), x_id, ndim, nel, isp)
      call xc_functl_init_functl(xcs%functional(FUNC_C, isp), c_id, ndim, nel, isp)

      call xc_functl_init_functl(xcs%kernel(FUNC_X, isp), xk_id, ndim, nel, isp)
      call xc_functl_init_functl(xcs%kernel(FUNC_C, isp), ck_id, ndim, nel, isp)

    end do

    xcs%family = ior(xcs%family, xcs%functional(FUNC_X,1)%family)
    xcs%family = ior(xcs%family, xcs%functional(FUNC_C,1)%family)

    xcs%kernel_family = ior(xcs%kernel_family, xcs%kernel(FUNC_X,1)%family)
    xcs%kernel_family = ior(xcs%kernel_family, xcs%kernel(FUNC_C,1)%family)

    ! Take care of hybrid functionals (they appear in the correlation functional)
    xcs%exx_coef = M_ZERO
    ll =  (hartree_fock) &
      .or.(xcs%functional(FUNC_X,1)%id == XC_OEP_X) &
      .or.(iand(xcs%functional(FUNC_C,1)%family, XC_FAMILY_HYB_GGA) /= 0) &
      .or.(iand(xcs%functional(FUNC_C,1)%family, XC_FAMILY_HYB_MGGA) /= 0)
    if(ll) then
      if((xcs%functional(FUNC_X,1)%id /= 0).and.(xcs%functional(FUNC_X,1)%id /= XC_OEP_X)) then
        message(1) = "You cannot use an exchange functional when performing"
        message(2) = "a Hartree-Fock calculation or using a hybrid functional."
        call messages_fatal(2)
      end if

      if(periodic_dim == ndim) &
        call messages_experimental("Fock operator (Hartree-Fock, OEP, hybrids) in fully periodic systems")

      ! get the mixing coefficient for hybrids
      if(iand(xcs%functional(FUNC_C,1)%family, XC_FAMILY_HYB_GGA) /= 0 .or. &
         iand(xcs%functional(FUNC_C,1)%family, XC_FAMILY_HYB_MGGA) /= 0) then        
        call XC_F90(hyb_exx_coef)(xcs%functional(FUNC_C,1)%conf, xcs%exx_coef)
      else
        ! we are doing Hartree-Fock plus possibly a correlation functional
        xcs%exx_coef = M_ONE
      end if

      ! reset certain variables
      xcs%functional(FUNC_X,1)%family = XC_FAMILY_OEP
      xcs%functional(FUNC_X,1)%id     = XC_OEP_X
      xcs%family             = ior(xcs%family, XC_FAMILY_OEP)
    end if

    if (iand(xcs%family, XC_FAMILY_LCA) /= 0) &
      call messages_not_implemented("LCA current functionals") ! not even in libxc!

    call messages_obsolete_variable('MGGAimplementation')
    call messages_obsolete_variable('CurrentInTau', 'XCUseGaugeIndependentKED')

    if(iand(xcs%family, XC_FAMILY_MGGA) /= 0 .or. iand(xcs%family, XC_FAMILY_HYB_MGGA) /= 0) then
      !%Variable XCUseGaugeIndependentKED
      !%Type logical
      !%Default yes
      !%Section Hamiltonian::XC
      !%Description
      !% If true, when evaluating the XC functional, a term including the (paramagnetic or total) current
      !% is added to the kinetic-energy density such as to make it gauge-independent.
      !% Applies only to meta-GGA (and hybrid meta-GGA) functionals.
      !%End
      call parse_variable('XCUseGaugeIndependentKED', .true., xcs%use_gi_ked)
    end if

    POP_SUB(xc_init)

  contains 

    subroutine parse()

      PUSH_SUB(xc_init.parse)

      ! the values of x_id,  c_id, xk_id, and c_id are read outside the routine
      
      !%Variable XCKernelLRCAlpha
      !%Type float
      !%Default 0.0
      !%Section Hamiltonian::XC
      !%Description
      !% Set to a non-zero value to add a long-range correction for solids to the kernel.
      !% This is the <math>\alpha</math> parameter defined in S. Botti <i>et al.</i>, <i>Phys. Rev. B</i>
      !% 69, 155112 (2004), which results in multiplying the Hartree term by
      !% <math>1 - \alpha / 4 \pi</math>. (Experimental)
      !%End

      call parse_variable('XCKernelLRCAlpha', M_ZERO, xcs%kernel_lrc_alpha)
      if(abs(xcs%kernel_lrc_alpha) > M_EPSILON) &
        call messages_experimental("Long-range correction to kernel")

      !%Variable XCDensityCorrection
      !%Type integer
      !%Default none
      !%Section Hamiltonian::XC::DensityCorrection
      !%Description
      !% This variable controls the long-range correction of the XC
      !% potential using the <a href=http://arxiv.org/abs/1107.4339>XC density representation</a>.
      !%Option none 0
      !% No correction is applied.
      !%Option long_range_x 1
      !% The correction is applied to the exchange potential.
      !%End
      call parse_variable('XCDensityCorrection', LR_NONE, xcs%xc_density_correction)

      if(xcs%xc_density_correction /= LR_NONE) then 
        call messages_experimental('XC density correction')

        !%Variable XCDensityCorrectionOptimize
        !%Type logical
        !%Default true
        !%Section Hamiltonian::XC::DensityCorrection
        !%Description
        !% When enabled, the density cutoff will be
        !% optimized to replicate the boundary conditions of the exact
        !% XC potential. If the variable is set to no, the value of
        !% the cutoff must be given by the <tt>XCDensityCorrectionCutoff</tt>
        !% variable.
        !%End
        call parse_variable('XCDensityCorrectionOptimize', .true., xcs%xcd_optimize_cutoff)

        !%Variable XCDensityCorrectionCutoff
        !%Type float
        !%Default 0.0
        !%Section Hamiltonian::XC::DensityCorrection
        !%Description
        !% The value of the cutoff applied to the XC density.
        !%End
        call parse_variable('XCDensityCorrectionCutoff', CNST(0.0), xcs%xcd_ncutoff)

        !%Variable XCDensityCorrectionMinimum
        !%Type logical
        !%Default true
        !%Section Hamiltonian::XC::DensityCorrection
        !%Description
        !% When enabled, the cutoff optimization will
        !% return the first minimum of the <math>q_{xc}</math> function if it does
        !% not find a value of -1 (<a href=http://arxiv.org/abs/1107.4339>details</a>).
        !% This is required for atoms or small
        !% molecules, but may cause numerical problems.
        !%End
        call parse_variable('XCDensityCorrectionMinimum', .true., xcs%xcd_minimum)

        !%Variable XCDensityCorrectionNormalize
        !%Type logical
        !%Default true
        !%Section Hamiltonian::XC::DensityCorrection
        !%Description
        !% When enabled, the correction will be
        !% normalized to reproduce the exact boundary conditions of
        !% the XC potential.
        !%End
        call parse_variable('XCDensityCorrectionNormalize', .true., xcs%xcd_normalize)

      end if

      !%Variable XCParallel
      !%Type logical
      !%Default false
      !%Section Execution::Parallelization
      !%Description
      !% (Experimental) When enabled, additional parallelization
      !% will be used for the calculation of the XC functional.
      !%End
      call parse_variable('XCParallel', .false., xcs%parallel)

      if(xcs%parallel) call messages_experimental('XCParallel')
      
      POP_SUB(xc_init.parse)
    end subroutine parse

  end subroutine xc_init


  ! ---------------------------------------------------------
  subroutine xc_end(xcs)
    type(xc_t), intent(inout) :: xcs

    integer :: isp

    PUSH_SUB(xc_end)

    do isp = 1, 2
      call xc_functl_end(xcs%functional(FUNC_X, isp))
      call xc_functl_end(xcs%functional(FUNC_C, isp))
      call xc_functl_end(xcs%kernel(FUNC_X, isp))
      call xc_functl_end(xcs%kernel(FUNC_C, isp))
    end do
    xcs%family = 0

    POP_SUB(xc_end)
  end subroutine xc_end

  ! ---------------------------------------------------------
  logical function xc_is_orbital_dependent(xcs)
    type(xc_t), intent(in) :: xcs

    PUSH_SUB(xc_is_orbital_dependent)

    xc_is_orbital_dependent = xcs%exx_coef /= M_ZERO .or. &
      iand(xcs%functional(FUNC_X,1)%family, XC_FAMILY_OEP) /= 0 .or. &
      iand(xcs%family, XC_FAMILY_MGGA) /= 0

    POP_SUB(xc_is_orbital_dependent)
  end function xc_is_orbital_dependent


#include "vxc_inc.F90"
#include "fxc_inc.F90"
#include "kxc_inc.F90"

end module xc_oct_m


!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
