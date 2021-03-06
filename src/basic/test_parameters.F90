!! Copyright (C) 2015 X. Andrade
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
!! $Id: test_parameters.F90 15203 2016-03-19 13:15:05Z xavier $

#include "global.h"
module test_parameters_oct_m
  
  private
  
  public ::             &
    test_parameters_t

  type test_parameters_t
    integer :: repetitions
    integer :: min_blocksize
    integer :: max_blocksize
  end type test_parameters_t

end module test_parameters_oct_m

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
