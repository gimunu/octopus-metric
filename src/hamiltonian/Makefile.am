## Process this file with automake to produce Makefile.in

## Copyright (C) 2002 M. Marques, A. Castro, A. Rubio, G. Bertsch
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2, or (at your option)
## any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
## 02110-1301, USA.
##
## $Id: Makefile.am 15263 2016-04-08 22:26:03Z xavier $

noinst_LIBRARIES = libhamiltonian.a

libhamiltonian_a_SOURCES =         \
	energy.F90                 \
	kick.F90                   \
	lasers.F90                 \
	species_pot.F90            \
	rkb_projector.F90          \
	kb_projector.F90           \
	hgh_projector.F90          \
	projector.F90              \
	epot.F90                   \
	hamiltonian_base.F90       \
	hamiltonian.F90            \
	scf_tol.F90                \
	gauge_field.F90            \
	born_charges.F90           \
	projector_matrix.F90       \
	berry.F90                  \
	pcm.F90			   \
	scdm.F90                   \
	functionals.F90            \
	xc.F90                     \
	ion_interaction.F90        \
	hirshfeld.F90              \
	libvdwxc.F90               \
	vdw_ts.F90                 \
	vdw_ts_low.c               \
	boundary_op.F90            \
	oct_exchange.F90

noinst_HEADERS =                      \
	lasers_inc.F90                \
	kb_projector_inc.F90          \
	hgh_projector_inc.F90         \
	projector_inc.F90             \
	hamiltonian_base_inc.F90      \
	hamiltonian_inc.F90           \
	species_pot_inc.F90           \
	scdm_inc.F90                  \
	functionals_list.F90          \
	vxc_inc.F90                   \
	fxc_inc.F90                   \
	kxc_inc.F90                   \
	oct_exchange_inc.F90

include $(srcdir)/../common-rules.make

depend:
	@makedepf90 $(libhamiltonian_a_SOURCES)

gauge_field.o : gauge_field.F90 projector.o
lasers.o : lasers.F90 lasers_inc.F90
species_pot.o : species_pot.F90 species_pot_inc.F90
rkb_projector.o : rkb_projector.F90 species_pot.o 
kb_projector.o : kb_projector.F90 kb_projector_inc.F90 species_pot.o 
hgh_projector.o : hgh_projector.F90 hgh_projector_inc.F90 species_pot.o 
projector.o : projector.F90 projector_inc.F90 rkb_projector.o kb_projector.o hgh_projector.o species_pot.o
epot.o : epot.F90 projector.o lasers.o species_pot.o gauge_field.o kick.o ion_interaction.o
hamiltonian.o : hamiltonian.F90 hamiltonian_inc.F90 lasers.o projector.o epot.o gauge_field.o hamiltonian_base.o pcm.o scdm.o functionals.o boundary_op.o oct_exchange.o
scf_tol.o : scf_tol.F90 
hamiltonian_base.o : hamiltonian_base.F90 hamiltonian_base_inc.F90 projector.o epot.o projector_matrix.o xc.o
born_charges.o : born_charges.F90
projector_matrix.o : projector_matrix.F90
berry.o : berry.F90
kick.o : kick.F90
energy.o : energy.F90
pcm.o : pcm.F90
scdm.o : scdm.F90 scdm_inc.F90 xc.o
functionals.o : functionals.F90 libvdwxc.o
xc.o : xc.F90 kxc_inc.F90 fxc_inc.F90 vxc_inc.F90 functionals.o
ion_interaction.o : ion_interaction.F90
hirshfeld.o : hirshfeld.F90 species_pot.o
libvdwxc.o : libvdwxc.F90
vdw_ts.o : vdw_ts.F90 hirshfeld.o
boundary_op.o : boundary_op.F90
oct_exchange.o : oct_exchange_inc.F90 xc.o
