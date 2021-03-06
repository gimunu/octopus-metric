!! Copyright (C) 2010 X. Andrade
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
!! $Id: checksum_interface.F90 15203 2016-03-19 13:15:05Z xavier $

module checksum_interface_oct_m
  
  public ::                 &
    checksum_calculate

  interface
    subroutine checksum_calculate(algorithm, narray, array, checksum)
      implicit none
      integer,    intent(in)  :: algorithm
      integer,    intent(in)  :: narray
      integer,    intent(in)  :: array
      integer(8), intent(out) :: checksum
    end subroutine checksum_calculate
  end interface

end module checksum_interface_oct_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
