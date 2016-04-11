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
!! $Id: stencil_stargeneral.F90 10978 2013-07-11 15:28:46Z micael $

#include "global.h"

module stencil_stargeneral_m
  use global_m
  use messages_m
  use profiling_m
  use stencil_m

  private
  public ::                     &
    stencil_stargeneral_size_lapl, &
    stencil_stargeneral_extent,    &
    stencil_stargeneral_get_lapl,  &
    stencil_stargeneral_pol_lapl,  &
    stencil_stargeneral_size_grad, &
    stencil_stargeneral_get_grad,  &
    stencil_stargeneral_pol_grad

    latt_sym = 

contains

  ! ---------------------------------------------------------
  integer function stencil_stargeneral_size_lapl(dim, order) result(n)
    integer, intent(in) :: dim
    integer, intent(in) :: order

    PUSH_SUB(stencil_stargeneral_size_lapl)

    n = 2*dim*order + 1
    if(dim == 2) n = n + 12
    !FCC
    if(dim == 3) n = 2*dim*order * 2 + 1
!     !HEX
!     if(dim == 3) n = 2*dim*order + 2*order + 1

    POP_SUB(stencil_stargeneral_size_lapl)
  end function stencil_stargeneral_size_lapl


  ! ---------------------------------------------------------
  !> Returns maximum extension of the stencil in spatial direction
  !! dir = 1, 2, 3 for a given discretization order.
  integer function stencil_stargeneral_extent(dir, order)
    integer, intent(in) :: dir
    integer, intent(in) :: order

    integer :: extent

    PUSH_SUB(stencil_stargeneral_extent)

    extent = 0
    if(dir >= 1.or.dir <= 3) then
      if(order <= 2) then
        extent = 2
      else
        extent = order
      end if
    end if
    stencil_stargeneral_extent = extent

    POP_SUB(stencil_stargeneral_extent)
  end function stencil_stargeneral_extent


  ! ---------------------------------------------------------
  integer function stencil_stargeneral_size_grad(dim, order) result(n)
    integer, intent(in) :: dim
    integer, intent(in) :: order

    PUSH_SUB(stencil_stargeneral_size_grad)

    n = 2*order + 1
    if(dim == 2) n = n + 2
    if(dim == 3) n = n + 4

    POP_SUB(stencil_stargeneral_size_grad)
  end function stencil_stargeneral_size_grad


  ! ---------------------------------------------------------
  subroutine stencil_stargeneral_get_lapl(this, dim, order)
    type(stencil_t), intent(out) :: this
    integer,         intent(in)  :: dim
    integer,         intent(in)  :: order

    integer :: i, j, n
    logical :: got_center

    PUSH_SUB(stencil_stargeneral_get_lapl)

    call stencil_allocate(this, stencil_stargeneral_size_lapl(dim, order))

    n = 1
    select case(dim)
    case(1)
      n = 1
      do i = 1, dim
        do j = -order, order
          if(j == 0) cycle
          n = n + 1
          this%points(i, n) = j
        end do
      end do
    case(2)
      n = 1
      do i = 1, dim
        do j = -order, order
          if(j == 0) cycle
          n = n + 1
          this%points(i, n) = j
        end do
      end do
      n = n + 1; this%points(1:2, n) = (/ -2,  1 /)
      n = n + 1; this%points(1:2, n) = (/ -2, -1 /)
      n = n + 1; this%points(1:2, n) = (/ -1,  2 /)
      n = n + 1; this%points(1:2, n) = (/ -1,  1 /)
      n = n + 1; this%points(1:2, n) = (/ -1, -1 /)
      n = n + 1; this%points(1:2, n) = (/ -1, -2 /)
      n = n + 1; this%points(1:2, n) = (/  1,  2 /)
      n = n + 1; this%points(1:2, n) = (/  1,  1 /)
      n = n + 1; this%points(1:2, n) = (/  1, -1 /)
      n = n + 1; this%points(1:2, n) = (/  1, -2 /)
      n = n + 1; this%points(1:2, n) = (/  2,  1 /)
      n = n + 1; this%points(1:2, n) = (/  2, -1 /)
    case(3)
      got_center = .false.
      
      n = 0
      do i = 1, dim
        do j = -order, order
          
          ! count center only once
          if(j == 0) then
            if(got_center) then
              cycle
            else
              got_center = .true.
            end if

          end if
          n = n + 1
          this%points(i, n) = j
        end do
      end do
      
      !FCC
      do j = -order, order
        if(j == 0) cycle
        n = n + 1
        this%points(1:3, n) = (/j,-j,0/)
        n = n + 1
        this%points(1:3, n) = (/j,0,-j/)
        n = n + 1
        this%points(1:3, n) = (/0,j,-j/)

      end do

      !HEX
!       do j = -order, order
!         if(j == 0) cycle
!         n = n + 1
!         this%points(1:3, n) = (/j,-j,0/)
!
!       end do


      print *, "(stencil_stargeneral_get_lapl) n = ", n
      
      do i=1, n
        print *, i, "this%points(1:3, n) = ", this%points(1:3, i) 
      end do
      
      
      
      

    end select

    call stencil_init_center(this)

    POP_SUB(stencil_stargeneral_get_lapl)
  end subroutine stencil_stargeneral_get_lapl


  ! ---------------------------------------------------------
  subroutine stencil_stargeneral_get_grad(this, dim, dir, order)
    type(stencil_t), intent(out) :: this
    integer,         intent(in)  :: dim
    integer,         intent(in)  :: dir
    integer,         intent(in)  :: order

    integer :: i, n, j

    PUSH_SUB(stencil_stargeneral_get_grad)

    call stencil_allocate(this, stencil_stargeneral_size_grad(dim, order))

    n = 1
    do i = -order, order
      this%points(dir, n) = i
      n = n + 1
    end do
    do j = 1, dim
      if(j==dir) cycle
      this%points(j, n) = -1
      n = n + 1
      this%points(j, n) =  1
      n = n + 1
    end do

    call stencil_init_center(this)

    POP_SUB(stencil_stargeneral_get_grad)
  end subroutine stencil_stargeneral_get_grad


  ! ---------------------------------------------------------
  subroutine stencil_stargeneral_pol_lapl(dim, order, pol)
    integer, intent(in)  :: dim
    integer, intent(in)  :: order
    integer, intent(out) :: pol(:,:) !< pol(dim, order)

    integer :: i, j, n

    PUSH_SUB(stencil_stargeneral_pol_lapl)

    n = 1
    select case(dim)
    case(1)
      n = 1
      pol(:,:) = 0
      do i = 1, dim
        do j = 1, 2*order
          n = n + 1
          pol(i, n) = j
        end do
      end do
    case(2)
      n = 1
      pol(:,:) = 0
      do i = 1, dim
        do j = 1, 2*order
          n = n + 1
          pol(i, n) = j
        end do
      end do
      n = n + 1; pol(1:2, n) = (/ 1, 1 /)
      n = n + 1; pol(1:2, n) = (/ 1, 2 /)
      n = n + 1; pol(1:2, n) = (/ 1, 3 /)
      n = n + 1; pol(1:2, n) = (/ 1, 4 /)
      n = n + 1; pol(1:2, n) = (/ 2, 1 /)
      n = n + 1; pol(1:2, n) = (/ 2, 2 /)
      n = n + 1; pol(1:2, n) = (/ 2, 3 /)
      n = n + 1; pol(1:2, n) = (/ 2, 4 /)
      n = n + 1; pol(1:2, n) = (/ 3, 1 /)
      n = n + 1; pol(1:2, n) = (/ 3, 2 /)
      n = n + 1; pol(1:2, n) = (/ 4, 1 /)
      n = n + 1; pol(1:2, n) = (/ 4, 2 /)
      
    case(3)
      n = 1
      pol(:,:) = 0
      do i = 1, dim
        do j = 1, 2*order
          n = n + 1
          pol(i, n) = j
        end do
      end do

      !FCC
      do j = 1, 2*order
        n = n + 1
        pol(1:3, n) = (/j,1,0/)
        n = n + 1
        pol(1:3, n) = (/1,0,j/)
        n = n + 1
        pol(1:3, n) = (/0,j,1/)
      end do
      
!       !HEX
!       do j = 1, 2*order
!         n = n + 1
!         pol(1:3, n) = (/j, 1, 0/)
!       end do
        

      
      
      print *, "(stencil_stargeneral_pol_lapl) n = ", n
      
      do i=1, n
        print *, i, "pol(1:3, n) = ", pol(1:3, i) 
      end do

    end select

    POP_SUB(stencil_stargeneral_pol_lapl)
  end subroutine stencil_stargeneral_pol_lapl


  ! ---------------------------------------------------------
  subroutine stencil_stargeneral_pol_grad(dim, dir, order, pol)
    integer, intent(in)  :: dim
    integer, intent(in)  :: dir
    integer, intent(in)  :: order
    integer, intent(out) :: pol(:,:) !< pol(dim, order)

    integer :: j, n

    PUSH_SUB(stencil_stargeneral_pol_grad)

    pol(:,:) = 0
    do j = 0, 2*order
      pol(dir, j+1) = j
    end do
    n = 2*order + 1

    select case(dim)
    case(2)
      select case(dir)
      case(1)
        n = n + 1; pol(1:2, n) = (/ 0, 1 /)
        n = n + 1; pol(1:2, n) = (/ 0, 2 /)
      case(2)
        n = n + 1; pol(1:2, n) = (/ 1, 0 /)
        n = n + 1; pol(1:2, n) = (/ 2, 0 /)
      end select
    case(3)
      select case(dir)
      case(1)
        n = n + 1; pol(1:3, n) = (/ 0, 1, 0 /)
        n = n + 1; pol(1:3, n) = (/ 0, 2, 0 /)
        n = n + 1; pol(1:3, n) = (/ 0, 0, 1 /)
        n = n + 1; pol(1:3, n) = (/ 0, 0, 2 /)
      case(2)
        n = n + 1; pol(1:3, n) = (/ 1, 0, 0 /)
        n = n + 1; pol(1:3, n) = (/ 2, 0, 0 /)
        n = n + 1; pol(1:3, n) = (/ 0, 0, 1 /)
        n = n + 1; pol(1:3, n) = (/ 0, 0, 2 /)
      case(3)
        n = n + 1; pol(1:3, n) = (/ 1, 0, 0 /)
        n = n + 1; pol(1:3, n) = (/ 2, 0, 0 /)
        n = n + 1; pol(1:3, n) = (/ 0, 1, 0 /)
        n = n + 1; pol(1:3, n) = (/ 0, 2, 0 /)
      end select
    end select

    POP_SUB(stencil_stargeneral_pol_grad)
  end subroutine stencil_stargeneral_pol_grad

end module stencil_stargeneral_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End: