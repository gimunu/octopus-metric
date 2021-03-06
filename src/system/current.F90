!! Copyright (C) 2008 X. Andrade
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
!! $Id: current.F90 15361 2016-05-12 04:16:28Z xavier $

#include "global.h"

module current_oct_m
  use batch_oct_m
  use batch_ops_oct_m
  use boundaries_oct_m
  use comm_oct_m
  use derivatives_oct_m
  use gauge_field_oct_m
  use geometry_oct_m
  use global_oct_m
  use grid_oct_m
  use hamiltonian_oct_m
  use hamiltonian_base_oct_m
  use io_oct_m
  use io_function_oct_m
  use lalg_basic_oct_m
  use logrid_oct_m
  use mesh_oct_m
  use mesh_function_oct_m
  use messages_oct_m
  use mpi_oct_m
  use parser_oct_m
  use poisson_oct_m
  use profiling_oct_m
  use projector_oct_m
  use ps_oct_m
  use restart_oct_m
  use simul_box_oct_m
  use species_oct_m
  use splines_oct_m
  use states_oct_m
  use states_dim_oct_m
  use submesh_oct_m
  use symmetries_oct_m
  use symmetrizer_oct_m
  use symm_op_oct_m
  use unit_oct_m
  use unit_system_oct_m
  use varinfo_oct_m

  implicit none

  private

  type current_t
    integer :: method
  end type current_t
    

  public ::                               &
    current_t,                            &
    current_init,                         &
    current_end,                          &
    current_calculate

  integer, parameter, public ::           &
    CURRENT_GRADIENT           = 1,       &
    CURRENT_GRADIENT_CORR      = 2,       &
    CURRENT_HAMILTONIAN        = 3,       &
    CURRENT_FAST               = 4

contains

  subroutine current_init(this)
    type(current_t), intent(out)   :: this

    PUSH_SUB(current_init)

    !%Variable CurrentDensity
    !%Default gradient_corrected
    !%Type integer
    !%Section Hamiltonian
    !%Description
    !% This variable selects the method used to
    !% calculate the current density. For the moment this variable is
    !% for development purposes and users should not need to use
    !% it.
    !%Option gradient 1
    !% The calculation of current is done using the gradient operator. (Experimental)
    !%Option gradient_corrected 2
    !% The calculation of current is done using the gradient operator
    !% with additional corrections for the total current from non-local operators.
    !%Option hamiltonian 3
    !% The current density is obtained from the commutator of the
    !% Hamiltonian with the position operator. (Experimental)
    !%Option gradient_corrected_fast 4
    !% More efficient version of the gradient_corrected calculation of the current. (Experimental)
    !%End

    call parse_variable('CurrentDensity', CURRENT_GRADIENT_CORR, this%method)
    if(.not.varinfo_valid_option('CurrentDensity', this%method)) call messages_input_error('CurrentDensity')
    if(this%method /= CURRENT_GRADIENT_CORR) then
      call messages_experimental("CurrentDensity /= gradient_corrected")
    end if
    
    POP_SUB(current_init)
  end subroutine current_init

  ! ---------------------------------------------------------

  subroutine current_end(this)
    type(current_t), intent(inout) :: this

    PUSH_SUB(current_end)


    POP_SUB(current_end)
  end subroutine current_end

  ! ---------------------------------------------------------
  subroutine current_calculate(this, der, hm, geo, st, current)
    type(current_t),      intent(in)    :: this
    type(derivatives_t),  intent(inout) :: der
    type(hamiltonian_t),  intent(in)    :: hm
    type(geometry_t),     intent(in)    :: geo
    type(states_t),       intent(inout) :: st
    FLOAT,                intent(out)    :: current(:, :, :) !< current(1:der%mesh%np_part, 1:der%mesh%sb%dim, 1:st%d%nspin)

    integer :: ik, ist, idir, idim, iatom, ip, ib, ii, ierr, ispin
    CMPLX, allocatable :: gpsi(:, :, :), psi(:, :), hpsi(:, :), rhpsi(:, :), rpsi(:, :), hrpsi(:, :)
    FLOAT, allocatable :: symmcurrent(:, :)
    type(profile_t), save :: prof
    type(symmetrizer_t) :: symmetrizer
    type(batch_t) :: hpsib, rhpsib, rpsib, hrpsib, epsib
    type(batch_t), allocatable :: commpsib(:)
    logical, parameter :: hamiltonian_current = .false.

    call profiling_in(prof, "CURRENT")
    PUSH_SUB(current_calculate)

    ! spin not implemented or tested
    ASSERT(all(ubound(current) == (/der%mesh%np_part, der%mesh%sb%dim, st%d%nspin/)))

    SAFE_ALLOCATE(psi(1:der%mesh%np_part, 1:st%d%dim))
    SAFE_ALLOCATE(gpsi(1:der%mesh%np, 1:der%mesh%sb%dim, 1:st%d%dim))
    SAFE_ALLOCATE(hpsi(1:der%mesh%np_part, 1:st%d%dim))
    SAFE_ALLOCATE(rhpsi(1:der%mesh%np_part, 1:st%d%dim))
    SAFE_ALLOCATE(rpsi(1:der%mesh%np_part, 1:st%d%dim))
    SAFE_ALLOCATE(hrpsi(1:der%mesh%np_part, 1:st%d%dim))
    SAFE_ALLOCATE(commpsib(1:der%mesh%sb%dim))

    current = M_ZERO

    select case(this%method)
    case(CURRENT_FAST)

      do ik = st%d%kpt%start, st%d%kpt%end
        ispin = states_dim_get_spin_index(st%d, ik)
        do ib = st%group%block_start, st%group%block_end

          call batch_pack(st%group%psib(ib, ik), copy = .true.)
          call batch_copy(st%group%psib(ib, ik), epsib)
          call boundaries_set(der%boundaries, st%group%psib(ib, ik))
          
          if(associated(hm%hm_base%phase)) then
            call zhamiltonian_base_phase(hm%hm_base, der, der%mesh%np_part, ik, &
              conjugate = .false., psib = epsib, src = st%group%psib(ib, ik))
          else
            call batch_copy_data(der%mesh%np_part, st%group%psib(ib, ik), epsib)
          end if

          do idir = 1, der%mesh%sb%dim
            call batch_copy(st%group%psib(ib, ik), commpsib(idir))
            call zderivatives_batch_perform(der%grad(idir), der, epsib, commpsib(idir), set_bc = .false.)
          end do
          
          call zhamiltonian_base_nlocal_position_commutator(hm%hm_base, der%mesh, st%d, ik, epsib, commpsib)

          do idir = 1, der%mesh%sb%dim

            if(associated(hm%hm_base%phase)) then
              call zhamiltonian_base_phase(hm%hm_base, der, der%mesh%np_part, ik, conjugate = .true., psib = commpsib(idir))
            end if
            
            do ist = states_block_min(st, ib), states_block_max(st, ib)

              do idim = 1, st%d%dim
                ii = batch_inv_index(st%group%psib(ib, ik), (/ist, idim/))
                call batch_get_state(st%group%psib(ib, ik), ii, der%mesh%np, psi(:, idim))
                call batch_get_state(commpsib(idir), ii, der%mesh%np, hrpsi(:, idim))
              end do
              
              do idim = 1, st%d%dim
                !$omp parallel do
                do ip = 1, der%mesh%np
                  current(ip, idir, ispin) = &
                    current(ip, idir, ispin) + st%d%kweights(ik)*st%occ(ist, ik)*aimag(conjg(psi(ip, idim))*hrpsi(ip, idim))
                end do
                !$omp end parallel do
              end do
              
            end do

            call batch_end(commpsib(idir))

          end do

          call batch_end(epsib)
          call batch_unpack(st%group%psib(ib, ik), copy = .false.)

        end do
      end do
    
    case(CURRENT_HAMILTONIAN)

      do ik = st%d%kpt%start, st%d%kpt%end
        ispin = states_dim_get_spin_index(st%d, ik)
        do ib = st%group%block_start, st%group%block_end

          call batch_pack(st%group%psib(ib, ik), copy = .true.)

          call batch_copy(st%group%psib(ib, ik), hpsib)
          call batch_copy(st%group%psib(ib, ik), rhpsib)
          call batch_copy(st%group%psib(ib, ik), rpsib)
          call batch_copy(st%group%psib(ib, ik), hrpsib)

          call boundaries_set(der%boundaries, st%group%psib(ib, ik))
          call zhamiltonian_apply_batch(hm, der, st%group%psib(ib, ik), hpsib, ik, set_bc = .false.)

          do idir = 1, der%mesh%sb%dim

            call batch_mul(der%mesh%np, der%mesh%x(:, idir), hpsib, rhpsib)
            call batch_mul(der%mesh%np_part, der%mesh%x(:, idir), st%group%psib(ib, ik), rpsib)
          
            call zhamiltonian_apply_batch(hm, der, rpsib, hrpsib, ik, set_bc = .false.)

            do ist = states_block_min(st, ib), states_block_max(st, ib)

              do idim = 1, st%d%dim
                ii = batch_inv_index(st%group%psib(ib, ik), (/ist, idim/))
                call batch_get_state(st%group%psib(ib, ik), ii, der%mesh%np, psi(:, idim))
                call batch_get_state(hrpsib, ii, der%mesh%np, hrpsi(:, idim))
                call batch_get_state(rhpsib, ii, der%mesh%np, rhpsi(:, idim))
              end do
              
              do idim = 1, st%d%dim
                !$omp parallel do
                do ip = 1, der%mesh%np
                  current(ip, idir, ispin) = current(ip, idir, ispin) &
                    - st%d%kweights(ik)*st%occ(ist, ik)&
                    *aimag(conjg(psi(ip, idim))*hrpsi(ip, idim) - conjg(psi(ip, idim))*rhpsi(ip, idim))
                end do
                !$omp end parallel do
              end do
              
            end do
            
          end do

          call batch_unpack(st%group%psib(ib, ik), copy = .false.)
          
          call batch_end(hpsib)
          call batch_end(rhpsib)
          call batch_end(rpsib)
          call batch_end(hrpsib)

        end do
      end do
    
    case(CURRENT_GRADIENT, CURRENT_GRADIENT_CORR)

      do ik = st%d%kpt%start, st%d%kpt%end
        ispin = states_dim_get_spin_index(st%d, ik)
        do ist = st%st_start, st%st_end
          
          call states_get_state(st, der%mesh, ist, ik, psi)
          
          do idim = 1, st%d%dim
            call boundaries_set(der%boundaries, psi(:, idim))
          end do

          if(associated(hm%hm_base%phase)) then 
            ! Apply the phase that contains both the k-point and vector-potential terms.
            do idim = 1, st%d%dim
              !$omp parallel do
              do ip = 1, der%mesh%np_part
                psi(ip, idim) = hm%hm_base%phase(ip, ik)*psi(ip, idim)
              end do
              !$omp end parallel do
            end do
          end if

          do idim = 1, st%d%dim
            call zderivatives_grad(der, psi(:, idim), gpsi(:, :, idim), set_bc = .false.)
          end do
          
          if(this%method == CURRENT_GRADIENT_CORR) then

            do idir = 1, der%mesh%sb%dim
              do iatom = 1, geo%natoms
                if(species_is_ps(geo%atom(iatom)%species)) then
                  call zprojector_commute_r(hm%ep%proj(iatom), der%mesh, st%d%dim, idir, ik, psi, gpsi(:, idir, :))
                end if
              end do
            end do
          
          end if

          do idir = 1, der%mesh%sb%dim
            
            do idim = 1, st%d%dim
              !$omp parallel do
              do ip = 1, der%mesh%np
                current(ip, idir, ispin) = current(ip, idir, ispin) + &
                  st%d%kweights(ik)*st%occ(ist, ik)*aimag(conjg(psi(ip, idim))*gpsi(ip, idir, idim))
              end do
              !$omp end parallel do
            end do
          end do

        end do
      end do
      
    case default

      ASSERT(.false.)

    end select

    if(st%parallel_in_states .or. st%d%kpt%parallel) then
      ! TODO: this could take dim = (/der%mesh%np, der%mesh%sb%dim, st%d%nspin/)) to reduce the amount of data copied
      call comm_allreduce(st%st_kpt_mpi_grp%comm, current) 
    end if
    
    if(der%mesh%sb%kpoints%use_symmetries) then
      SAFE_ALLOCATE(symmcurrent(1:der%mesh%np, 1:der%mesh%sb%dim))
      call symmetrizer_init(symmetrizer, der%mesh)
      do ispin = 1, st%d%nspin
        call dsymmetrizer_apply(symmetrizer, field_vector = current(:, :, ispin), symmfield_vector = symmcurrent, &
          suppress_warning = .true.)
        current(1:der%mesh%np, 1:der%mesh%sb%dim, ispin) = symmcurrent(1:der%mesh%np, 1:der%mesh%sb%dim)
      end do
      call symmetrizer_end(symmetrizer)
      SAFE_DEALLOCATE_A(symmcurrent)
    end if

    SAFE_DEALLOCATE_A(gpsi)

    call profiling_out(prof)
    POP_SUB(current_calculate)

  end subroutine current_calculate

end module current_oct_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
