#include "global.h"

module atom_oct_m
  use global_oct_m
  use json_oct_m
  use messages_oct_m
  use profiling_oct_m
  use species_oct_m
  use unit_oct_m
  use unit_system_oct_m

  implicit none

  private
  public ::                               &
    atom_init,                            &
    atom_init_from_data_object,           &
    atom_end,                             &
    atom_create_data_object,              &
    atom_get_label,                       &
    atom_set_species,                     &
    atom_get_species,                     &
    atom_same_species,                    &
    atom_distance,                        &
    atom_write_xyz,                       &
    atom_classical_init,                  &
    atom_classical_init_from_data_object, &
    atom_classical_end,                   &
    atom_classical_create_data_object,    &
    atom_classical_get_label,             &
    atom_classical_write_xyz

  type, public :: atom_t
    !private
    character(len=LABEL_LEN)  :: label = ""
    type(species_t), pointer  :: species  =>null() !< pointer to species
    FLOAT, dimension(MAX_DIM) :: x     = M_ZERO !< position of atom in real space
    FLOAT, dimension(MAX_DIM) :: v     = M_ZERO !< velocity of atom in real space
    FLOAT, dimension(MAX_DIM) :: f     = M_ZERO !< force on atom in real space
    logical                   :: move  = .true. !< should I move this atom in the optimization mode
  end type atom_t

  type, public :: atom_classical_t
    !private
    character(len=LABEL_LEN)  :: label  = ""
    FLOAT, dimension(MAX_DIM) :: x      = M_ZERO
    FLOAT, dimension(MAX_DIM) :: v      = M_ZERO
    FLOAT, dimension(MAX_DIM) :: f      = M_ZERO
    FLOAT                     :: charge = M_ZERO
  end type atom_classical_t

  interface atom_same_species
    module procedure atom_same_species_aa
    module procedure atom_same_species_as
    !GFORTRAN objects to the next procedure, possibly a compiler bug
    !module procedure atom_same_species_sa
  end interface atom_same_species

contains

  ! ---------------------------------------------------------
  subroutine atom_init(this, label, x, species, move)
    type(atom_t),                      intent(out) :: this
    character(len=*),                  intent(in)  :: label
    FLOAT, dimension(:),               intent(in)  :: x
    type(species_t), target, optional, intent(in)  :: species
    logical,                 optional, intent(in)  :: move

    PUSH_SUB(atom_init)

    this%label = trim(adjustl(label))
    this%species  =>null()
    if(present(species))this%species=>species
    this%x     = x
    this%v     = M_ZERO
    this%f     = M_ZERO
    this%move  = .true.
    if(present(move))this%move=move

    POP_SUB(atom_init)
  end subroutine atom_init

  ! ---------------------------------------------------------
  elemental subroutine atom_end(this)
    type(atom_t), intent(inout) :: this

    this%label = ""
    this%species  =>null()
    this%x     = M_ZERO
    this%v     = M_ZERO
    this%f     = M_ZERO
    this%move  = .true.

  end subroutine atom_end

  ! ---------------------------------------------------------
  subroutine atom_init_from_data_object(this, species, json)
    type(atom_t),            intent(out) :: this
    type(species_t), target, intent(in)  :: species
    type(json_object_t),     intent(in)  :: json

    integer :: ierr

    PUSH_SUB(atom_init_from_data_object)

    call json_get(json, "label", this%label, ierr)
    if(ierr/=JSON_OK)then
      message(1) = 'Could not read "label" from atom data object.'
      call messages_fatal(1)
    end if
    ASSERT(atom_get_label(this)==species_label(species))
    this%species=>species
    call json_get(json, "x", this%x, ierr)
    if(ierr/=JSON_OK)then
      message(1) = 'Could not read "x" (coordinates) from atom data object.'
      call messages_fatal(1)
    end if
    this%v=M_ZERO
    this%f=M_ZERO
    this%move=.true.

    POP_SUB(atom_init_from_data_object)
  end subroutine atom_init_from_data_object

  ! ---------------------------------------------------------
  subroutine atom_create_data_object(this, json)
    type(atom_t),        intent(in)  :: this
    type(json_object_t), intent(out) :: json

    PUSH_SUB(atom_create_data_object)

    call json_init(json)
    call json_set(json, "label", trim(adjustl(this%label)))
    call json_set(json, "x", this%x)

    POP_SUB(atom_create_data_object)
  end subroutine atom_create_data_object

  ! ---------------------------------------------------------
  pure function atom_get_label(this) result(label)
    type(atom_t), intent(in) :: this

    character(len=len_trim(adjustl(this%label))) :: label

    label=trim(adjustl(this%label))

  end function atom_get_label
  
  ! ---------------------------------------------------------
  subroutine atom_set_species(this, species)
    type(atom_t),            intent(inout) :: this
    type(species_t), target, intent(in)    :: species

    PUSH_SUB(atom_set_species)

    this%species=>species
    POP_SUB(atom_set_species)

  end subroutine atom_set_species
  
  ! ---------------------------------------------------------
  subroutine atom_get_species(this, species)
    type(atom_t),    target,  intent(in)  :: this
    type(species_t), pointer, intent(out) :: species

    ! NO PUSH_SUB, called too often

    species => null()
    if(associated(this%species)) species => this%species

  end subroutine atom_get_species
  
  ! ---------------------------------------------------------
  elemental function atom_same_species_aa(this, that) result(is)
    type(atom_t), intent(in) :: this
    type(atom_t), intent(in) :: that

    logical :: is

    is=(atom_get_label(this)==atom_get_label(that))

  end function atom_same_species_aa

  ! ---------------------------------------------------------
  elemental function atom_same_species_as(this, species) result(is)
    type(atom_t),    intent(in) :: this
    type(species_t), intent(in) :: species

    logical :: is

    is=(atom_get_label(this)==species_label(species))

  end function atom_same_species_as

  ! ---------------------------------------------------------
  elemental function atom_same_species_sa(species, this) result(is)
    type(species_t), intent(in) :: species
    type(atom_t),    intent(in) :: this

    logical :: is

    is=(atom_get_label(this)==species_label(species))

  end function atom_same_species_sa

  ! ---------------------------------------------------------
  elemental function atom_distance(this_1, this_2) result(dst)
    type(atom_t), intent(in) :: this_1
    type(atom_t), intent(in) :: this_2

    FLOAT :: dst

    dst=sqrt(sum((this_1%x-this_2%x)**2))

  end function atom_distance

  ! ---------------------------------------------------------
  subroutine atom_write_xyz(this, dim, unit)
    type(atom_t),      intent(in) :: this
    integer, optional, intent(in) :: dim
    integer,           intent(in) :: unit

    character(len=19) :: frmt
    integer           :: i, dim_

    PUSH_SUB(atom_write_xyz)

    dim_=MAX_DIM
    if(present(dim))dim_=dim
    write(unit=frmt, fmt="(a5,i2.2,a4,i2.2,a6)") "(6x,a", LABEL_LEN, ",2x,", dim_,"f12.6)"
    write(unit=unit, fmt=frmt) this%label, (units_from_atomic(units_out%length_xyz_file, this%x(i)), i=1, dim_)

    POP_SUB(atom_write_xyz)

  end subroutine atom_write_xyz

  ! ---------------------------------------------------------
  pure subroutine atom_classical_init(this, label, x, charge)
    type(atom_classical_t), intent(out) :: this
    character(len=*),       intent(in)  :: label
    FLOAT,    dimension(:), intent(in)  :: x
    FLOAT,                  intent(in)  :: charge

    this%label  = trim(adjustl(label))
    this%x      = x
    this%v      = M_ZERO
    this%f      = M_ZERO
    this%charge = charge

  end subroutine atom_classical_init

  ! ---------------------------------------------------------
  elemental subroutine atom_classical_end(this)
    type(atom_classical_t), intent(inout) :: this

    this%label  = ""
    this%x      = M_ZERO
    this%v      = M_ZERO
    this%f      = M_ZERO
    this%charge = M_ZERO

  end subroutine atom_classical_end

  ! ---------------------------------------------------------
  subroutine atom_classical_init_from_data_object(this, json)
    type(atom_classical_t), intent(out) :: this
    type(json_object_t),    intent(in)  :: json

    integer :: ierr

    PUSH_SUB(atom_classical_init_from_data_object)

    call json_get(json, "label", this%label, ierr)
    if(ierr/=JSON_OK)then
      message(1) = 'Could not read "label" from atom classical data object.'
      call messages_fatal(1)
    end if
    call json_get(json, "x", this%x, ierr)
    if(ierr/=JSON_OK)then
      message(1) = 'Could not read "x" (coordinates) from atom classical data object.'
      call messages_fatal(1)
    end if
    this%v=M_ZERO
    this%f=M_ZERO
    call json_get(json, "charge", this%charge, ierr)
    if(ierr/=JSON_OK)then
      message(1) = 'Could not read "charge" from atom classical data object.'
      call messages_fatal(1)
    end if
    POP_SUB(atom_classical_init_from_data_object)

  end subroutine atom_classical_init_from_data_object

  ! ---------------------------------------------------------
  subroutine atom_classical_create_data_object(this, json)
    type(atom_classical_t), intent(in)  :: this
    type(json_object_t),    intent(out) :: json

    PUSH_SUB(atom_classical_create_data_object)

    call json_init(json)
    call json_set(json, "label", trim(adjustl(this%label)))
    call json_set(json, "x", this%x)
    call json_set(json, "charge", this%charge)

    POP_SUB(atom_classical_create_data_object)
  end subroutine atom_classical_create_data_object

  ! ---------------------------------------------------------
  pure function atom_classical_get_label(this) result(label)
    type(atom_classical_t), intent(in) :: this
    !
    character(len=len_trim(adjustl(this%label))) :: label
    !
    label=trim(adjustl(this%label))
    return
  end function atom_classical_get_label
  
  ! ---------------------------------------------------------
  subroutine atom_classical_write_xyz(this, dim, unit)
    type(atom_classical_t), intent(in) :: this
    integer,      optional, intent(in) :: dim
    integer,                intent(in) :: unit

    character(len=27) :: frmt
    integer           :: i, dim_

    PUSH_SUB(atom_classical_write_xyz)
    dim_=MAX_DIM
    if(present(dim))dim_=dim
    write(unit=frmt, fmt="(a10,i2.2,a15)") "(6x,a1,2x,", dim_, "f12.6,a3,f12.6)"
    write(unit=unit, fmt=frmt) this%label(1:1), &
      (units_from_atomic(units_out%length_xyz_file, this%x(i)), i=1, dim_), " # ", this%charge

    POP_SUB(atom_classical_write_xyz)
  end subroutine atom_classical_write_xyz

end module atom_oct_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
