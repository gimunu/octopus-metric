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
!! $Id: eigen_cg.F90 15203 2016-03-19 13:15:05Z xavier $

#include "global.h"

module eigen_cg_oct_m
  use comm_oct_m
  use global_oct_m
  use grid_oct_m
  use hamiltonian_oct_m
  use io_oct_m
  use lalg_basic_oct_m
  use lalg_adv_oct_m
  use loct_oct_m
  use math_oct_m
  use mesh_oct_m
  use mesh_function_oct_m
  use messages_oct_m
  use mpi_oct_m
  use mpi_lib_oct_m
  use preconditioners_oct_m
  use profiling_oct_m
  use states_oct_m
  use states_calc_oct_m

  implicit none

  private
  public ::                 &
    deigensolver_cg2,       &
    zeigensolver_cg2,       &
    deigensolver_cg2_new,   &
    zeigensolver_cg2_new

contains

#include "real.F90"
#include "eigen_cg_inc.F90"
#include "undef.F90"

#include "complex.F90"
#include "eigen_cg_inc.F90"
#include "undef.F90"

end module eigen_cg_oct_m


!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
