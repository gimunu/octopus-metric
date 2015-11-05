/*
 Copyright (C) 2012 X. Andrade

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2, or (at your option)
 any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 02110-1301, USA.

 $Id: convert.cl 14305 2015-06-22 15:56:28Z dstrubbe $
*/

#include <cl_global.h>

__kernel void complex_to_double(const int np, __global const double2 * __restrict src, __global double * __restrict dest){
  int ip = get_global_id(0);
  
  if(ip < np) dest[ip] = src[ip].s0;

}

__kernel void double_to_complex(const int np, __global const double * __restrict src, __global double2 * __restrict dest){
  int ip = get_global_id(0);
  
  if(ip < np) dest[ip].s0 = src[ip];
  if(ip < np) dest[ip].s1 = 0.0;

}

/*
 Local Variables:
 mode: c
 coding: utf-8
 End:
*/
