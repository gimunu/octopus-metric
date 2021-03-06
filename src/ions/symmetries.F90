!! Copyright (C) 2009 X. Andrade
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
!! $Id: symmetries.F90 15415 2016-06-16 13:09:58Z xavier $

#include "global.h"

module symmetries_oct_m
  use geometry_oct_m
  use global_oct_m
  use messages_oct_m
  use mpi_oct_m
  use parser_oct_m
  use profiling_oct_m
  use species_oct_m
  use symm_op_oct_m
  use spglib_f08
  use lalg_adv_oct_m


  implicit none

  private
  
  public ::                        &
    symmetries_t,                  &
    symmetries_nullify,            &
    symmetries_init,               &
    symmetries_copy,               &
    symmetries_end,                &
    symmetries_number,             &
    symmetries_apply_kpoint,       &
    symmetries_space_group_number, &
    symmetries_have_break_dir,     &
    symmetries_identity_index

  type symmetries_t
    type(symm_op_t), allocatable :: ops(:)
    integer                  :: nops
    FLOAT                    :: breakdir(1:3)
    integer                  :: space_group
  end type symmetries_t

  real(8), parameter :: symprec = CNST(1e-5)

  !> NOTE: unfortunately, these routines use global variables shared among them
  interface
    subroutine symmetries_finite_init(natoms, types, positions, verbosity, point_group)
      integer, intent(in)  :: natoms
      integer, intent(in)  :: types !< (natoms)
      real(8), intent(in)  :: positions !< (3, natoms)
      integer, intent(in)  :: verbosity
      integer, intent(out) :: point_group
    end subroutine symmetries_finite_init

    subroutine symmetries_finite_get_group_name(point_group, name)
      integer,          intent(in)  :: point_group
      character(len=*), intent(out) :: name
    end subroutine symmetries_finite_get_group_name

    subroutine symmetries_finite_get_group_elements(point_group, elements)
      integer,          intent(in)  :: point_group
      character(len=*), intent(out) :: elements
    end subroutine symmetries_finite_get_group_elements

    subroutine symmetries_finite_end()
    end subroutine symmetries_finite_end
  end interface

contains
  
  elemental subroutine symmetries_nullify(this)
    type(symmetries_t), intent(out) :: this

    this%nops = 0
    this%breakdir = M_ZERO
    this%space_group = 0

  end subroutine symmetries_nullify

  subroutine symmetries_init(this, geo, dim, periodic_dim, rlattice)
    type(symmetries_t),  intent(out) :: this
    type(geometry_t),    intent(in)  :: geo
    integer,             intent(in)  :: dim
    integer,             intent(in)  :: periodic_dim
    FLOAT,               intent(in)  :: rlattice(:, :)

    integer :: max_size, fullnops, dim4syms
    integer :: idir, iatom, iop, verbosity, point_group
    real(8) :: determinant
    real(8) :: lattice(1:3, 1:3)
    real(8) :: klattice(1:3, 1:3)
    real(8), allocatable :: position(:, :)
    integer, allocatable :: typs(:)
    type(block_t) :: blk
    integer, allocatable :: rotation(:, :, :)
    real(8), allocatable :: translation(:, :)
    type(symm_op_t) :: tmpop
    character(len=6) :: group_name
    character(len=30) :: group_elements
    character(len=11) :: symbol
    integer :: natoms, identity(3,3)
    logical :: any_non_spherical, symmetries_compute, found_identity, is_supercell

    PUSH_SUB(symmetries_init)

    call messages_print_stress(stdout, "Symmetries")

    ! if someone cares, they could try to analyze the symmetry point group of the individual species too
    any_non_spherical = .false.
    do iatom = 1, geo%natoms
      any_non_spherical = any_non_spherical                          .or. &
        species_type(geo%atom(iatom)%species) == SPECIES_USDEF          .or. &
        species_type(geo%atom(iatom)%species) == SPECIES_JELLIUM_SLAB   .or. &
        species_type(geo%atom(iatom)%species) == SPECIES_CHARGE_DENSITY .or. &
        species_type(geo%atom(iatom)%species) == SPECIES_FROM_FILE      .or. &
        species_type(geo%atom(iatom)%species) == SPECIES_FROZEN
      if(any_non_spherical)exit
    end do
    if(any_non_spherical) then
      message(1) = "Symmetries are disabled since non-spherically symmetric species may be present."
      call messages_info(1)
      call messages_print_stress(stdout)
    end if

    !%Variable SymmetriesCompute
    !%Type logical
    !%Default (natoms < 100) ? true : false
    !%Section Execution::Symmetries
    !%Description
    !% If disabled, <tt>Octopus</tt> will not compute
    !% nor print the symmetries.
    !%End
    call parse_variable('SymmetriesCompute', (geo%natoms < 100), symmetries_compute)
    if(.not. symmetries_compute) then
      message(1) = "Symmetries have been disabled by SymmetriesCompute = false."
      call messages_info(1)
      call messages_print_stress(stdout)
    end if

    if(any_non_spherical .or. .not. symmetries_compute) then
      call init_identity()

      POP_SUB(symmetries_init)
      return
    end if

    dim4syms = min(3,dim)
    ! In all cases, we must check that the grid respects the symmetries. --DAS

    if (periodic_dim == 0) then

      call init_identity()

      ! for the moment symmetries are only used for information, so we compute them only on one node.
      if(mpi_grp_is_root(mpi_world)) then
        natoms = max(1,geo%natoms)

        SAFE_ALLOCATE(position(1:3, natoms))
        SAFE_ALLOCATE(typs(1:natoms))

        forall(iatom = 1:geo%natoms)
          position(1:3, iatom) = M_ZERO
          position(1:dim4syms, iatom) = geo%atom(iatom)%x(1:dim4syms)
          typs(iatom) = species_index(geo%atom(iatom)%species)
        end forall

        verbosity = -1
        
        if (symmetries_compute) then
          call symmetries_finite_init(geo%natoms, typs(1), position(1, 1), verbosity, point_group)
          call symmetries_finite_get_group_name(point_group, group_name)
          call symmetries_finite_get_group_elements(point_group, group_elements)
          call symmetries_finite_end()

          call messages_write('Symmetry elements : '//trim(group_elements), new_line = .true.)
          call messages_write('Symmetry group    : '//trim(group_name))
          call messages_info()
        end if
      end if

      SAFE_DEALLOCATE_A(position)
      SAFE_DEALLOCATE_A(typs)

    else

      ! get inverse matrix to extract reduced coordinates for spglib
      lattice(1:3, 1:3) = rlattice(1:3, 1:3)
      klattice = lattice
      determinant = lalg_determinant(3, klattice, invert=.true.)
      
      SAFE_ALLOCATE(position(1:3, 1:geo%natoms))  ! transpose!!
      SAFE_ALLOCATE(typs(1:geo%natoms))

      ! fix things for low-dimensional systems: higher dimension lattice constants set to 1
      do idir = dim + 1, 3
        lattice(idir, idir) = M_ONE
      end do

      do iatom = 1, geo%natoms
        position(1:3, iatom) = M_HALF
        ! position here contains reduced coordinates
        ! this should be matmul(klattice, geo atom x)
        position(1:dim4syms, iatom) = matmul (klattice, geo%atom(iatom)%x(1:dim4syms)) + M_HALF
        typs(iatom) = species_index(geo%atom(iatom)%species)
      end do

      ! transpose the lattice vectors for use in spglib as row-major matrix
      lattice(:,:) = transpose(lattice(:,:))

      this%space_group = spglib_get_international(symbol, lattice(1, 1), position(1, 1), typs(1), geo%natoms, symprec)

      if(this%space_group == 0) then
        message(1) = "Symmetry analysis failed in spglib. Disabling symmetries."
        call messages_warning(1)

        do iatom = 1, geo%natoms
          write(message(1),'(a,i6,a,3f12.6,a,3f12.6)') 'type ', typs(iatom), &
            ' reduced coords ', position(:, iatom), ' cartesian coords ', geo%atom(iatom)%x(:)
          call messages_info(1)
        end do

        call init_identity()
        SAFE_DEALLOCATE_A(rotation)
        SAFE_DEALLOCATE_A(translation)
        POP_SUB(symmetries_init)
        return
      end if

      write(message(1),'(a, i4)') 'Space group No. ', this%space_group
      write(message(2),'(2a)') 'International: ', symbol
      this%space_group = spglib_get_schoenflies(symbol, lattice(1, 1), position(1, 1), typs(1), geo%natoms, symprec)
      write(message(3),'(2a)') 'Schoenflies: ', symbol
      call messages_info(3)

      max_size = spglib_get_multiplicity(lattice(1, 1), position(1, 1), typs(1), geo%natoms, symprec)

      ! spglib returns row-major not column-major matrices!!! --DAS
      SAFE_ALLOCATE(rotation(1:3, 1:3, 1:max_size))
      SAFE_ALLOCATE(translation(1:3, 1:max_size))

      fullnops = spglib_get_symmetry(rotation(1, 1, 1), translation(1, 1), &
        max_size, lattice(1, 1), position(1, 1), typs(1), geo%natoms, symprec)

      ! we need to check that it is not a supercell, as in the QE routine (sgam_at)
      ! they disable fractional translations if the identity has one, because the sym ops might not form a group.
      ! spglib may return duplicate operations in this case!
      is_supercell = (fullnops > 48)
      found_identity = .false.
      identity = reshape((/1, 0, 0, 0, 1, 0, 0, 0, 1/), shape(identity))
      do iop = 1, fullnops
        if(all(rotation(1:3, 1:3, iop) == identity(1:3, 1:3))) then
          found_identity = .true.
          if(any(abs(translation(1:3, iop)) > real(symprec, REAL_PRECISION))) then
            is_supercell = .true.
            write(message(1),'(a,3f12.6)') 'Identity has a fractional translation ', translation(1:3, iop)
            call messages_info(1)
          end if
        end if
      end do
      if(.not. found_identity) then
        message(1) = "Symmetries internal error: Identity is missing from symmetry operations."
        call messages_fatal(1)
      end if
    
      if(is_supercell) then
        message(1) = "Disabling fractional translations. System appears to be a supercell."
        call messages_info(1)
      end if
      ! actually, we do not use fractional translations regardless currently

      ! this is a hack to get things working, this variable should be
      ! eliminated and the direction calculated automatically from the
      ! perturbations.

      !%Variable SymmetryBreakDir
      !%Type block
      !%Section Mesh::Simulation Box
      !%Description
      !% This variable specifies a direction in which the symmetry of
      !% the system will be broken. This is useful for generating <i>k</i>-point
      !% grids when an external perturbation is applied.
      !%End

      this%breakdir(1:3) = M_ZERO

      if(parse_block('SymmetryBreakDir', blk) == 0) then

        do idir = 1, dim4syms
          call parse_block_float(blk, 0, idir - 1, this%breakdir(idir))
        end do

        call parse_block_end(blk)

      end if

      SAFE_ALLOCATE(this%ops(1:fullnops))

      ! NOTE: HH 21/05/2016
      ! The below search for fractional translations doesnt seem to work for non-orthogonal cells,
      ! but not critical as it just returns less useable symmetries...
      ! FIXME

      ! check all operations and leave those that kept the symmetry-breaking
      ! direction invariant and (for the moment) that do not have a translation
      this%nops = 0
      write(message(1),'(a7,a31,12x,a33)') 'Index', 'Rotation matrix', 'Fractional translations'
      call messages_info(1)
      do iop = 1, fullnops
        ! sometimes spglib may return lattice vectors as 'fractional' translations
        translation(:, iop) = translation(:, iop) - int(translation(:, iop) + CNST(0.5)*symprec)
        call symm_op_init(tmpop, rotation(:, :, iop), real(translation(:, iop), REAL_PRECISION))

        if(symm_op_invariant(tmpop, this%breakdir, real(symprec, REAL_PRECISION)) &
          .and. .not. symm_op_has_translation(tmpop, real(symprec, REAL_PRECISION))) then
          this%nops = this%nops + 1
          call symm_op_copy(tmpop, this%ops(this%nops))

          write(message(1),'(i5,1x,a,2x,3(3i4,2x),3f12.6)') this%nops, ':', rotation(1:3, 1:3, iop), translation(1:3, iop)
          call messages_info(1)
        end if
        call symm_op_end(tmpop)
      end do

      write(message(1), '(a,i5,a)') 'Info: The system has ', this%nops, ' symmetries that can be used.'
      call messages_info()

      SAFE_DEALLOCATE_A(rotation)
      SAFE_DEALLOCATE_A(translation)
      SAFE_DEALLOCATE_A(position)
      SAFE_DEALLOCATE_A(typs)

    end if

    call messages_print_stress(stdout)

    POP_SUB(symmetries_init)
    
  contains

    subroutine init_identity()
      
      PUSH_SUB(symmetries_init.init_identity)
      
      SAFE_ALLOCATE(this%ops(1:1))
      this%nops = 1
      call symm_op_init(this%ops(1), reshape((/1, 0, 0, 0, 1, 0, 0, 0, 1/), (/3, 3/)))
      this%breakdir = M_ZERO
      this%space_group = 1
      
      POP_SUB(symmetries_init.init_identity)
      
    end subroutine init_identity

  end subroutine symmetries_init

  ! -------------------------------------------------------------------------------
  subroutine symmetries_copy(inp, outp)
    type(symmetries_t),  intent(in)  :: inp
    type(symmetries_t),  intent(out) :: outp

    integer :: iop

    PUSH_SUB(symmetries_copy)

    outp%nops = inp%nops
    outp%breakdir = inp%breakdir
    
    SAFE_ALLOCATE(outp%ops(1:outp%nops))

    do iop = 1, outp%nops
      call symm_op_copy(inp%ops(iop), outp%ops(iop))
    end do

    POP_SUB(symmetries_copy)
  end subroutine symmetries_copy

  ! -------------------------------------------------------------------------------

  subroutine symmetries_end(this)
    type(symmetries_t),  intent(inout) :: this

    integer :: iop

    PUSH_SUB(symmetries_end)

    if(allocated(this%ops)) then
      do iop = 1, this%nops
        call symm_op_end(this%ops(iop))
      end do

      SAFE_DEALLOCATE_A(this%ops)
    end if
    
    POP_SUB(symmetries_end)
  end subroutine symmetries_end

  ! -------------------------------------------------------------------------------
  
  integer pure function symmetries_number(this) result(number)
    type(symmetries_t),  intent(in) :: this
    
    number = this%nops
  end function symmetries_number

  ! -------------------------------------------------------------------------------

  subroutine symmetries_apply_kpoint(this, iop, aa, bb)
    type(symmetries_t),  intent(in)  :: this
    integer,             intent(in)  :: iop
    FLOAT,               intent(in)  :: aa(1:3)
    FLOAT,               intent(out) :: bb(1:3)

    PUSH_SUB(symmetries_apply_kpoint)

    ASSERT(0 < iop .and. iop <= this%nops)

    bb(1:3) = symm_op_apply_inv(this%ops(iop), aa(1:3))

    POP_SUB(symmetries_apply_kpoint)
  end subroutine symmetries_apply_kpoint

  ! -------------------------------------------------------------------------------

  integer pure function symmetries_space_group_number(this) result(number)
    type(symmetries_t),  intent(in) :: this
    
    number = this%space_group
  end function symmetries_space_group_number

  ! -------------------------------------------------------------------------------

  logical pure function symmetries_have_break_dir(this) result(have)
    type(symmetries_t),  intent(in)  :: this

    have = any(abs(this%breakdir(1:3)) > M_EPSILON)
  end function symmetries_have_break_dir

  ! -------------------------------------------------------------------------------

  integer pure function symmetries_identity_index(this) result(index)
    type(symmetries_t),  intent(in)  :: this

    integer :: iop
    
    do iop = 1, this%nops
      if(symm_op_is_identity(this%ops(iop))) then
        index = iop
        cycle
      end if
    end do

  end function symmetries_identity_index

end module symmetries_oct_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
