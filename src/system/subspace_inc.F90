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
!! $Id: subspace_inc.F90 15583 2016-08-15 13:45:41Z nicolastd $

! ---------------------------------------------------------
!> This routine diagonalises the Hamiltonian in the subspace defined by the states.
subroutine X(subspace_diag)(this, der, st, hm, ik, eigenval, diff)
  type(subspace_t),       intent(in)    :: this
  type(derivatives_t),    intent(in)    :: der
  type(states_t), target, intent(inout) :: st
  type(hamiltonian_t),    intent(in)    :: hm
  integer,                intent(in)    :: ik
  FLOAT,                  intent(out)   :: eigenval(:)
  FLOAT, optional,        intent(out)   :: diff(:)

  integer :: ist
  R_TYPE, allocatable :: psi(:, :, :)
    
  PUSH_SUB(X(subspace_diag))
  call profiling_in(diagon_prof, "SUBSPACE_DIAG")

  select case(this%method)
    
  case(OPTION__SUBSPACEDIAGONALIZATION__SCALAPACK)

    SAFE_ALLOCATE(psi(1:der%mesh%np_part, 1:st%d%dim, st%st_start:st%st_end))

    do ist = st%st_start, st%st_end
      call states_get_state(st, der%mesh, ist, ik, psi(:, :, ist))
    end do

    call X(subspace_diag_scalapack)(der, st, hm, ik, eigenval, psi, diff)

    do ist = st%st_start, st%st_end
      call states_set_state(st, der%mesh, ist, ik, psi(:, :, ist))
    end do
    
    SAFE_DEALLOCATE_A(psi)
    
  case(OPTION__SUBSPACEDIAGONALIZATION__STANDARD)
    call X(subspace_diag_standard)(der, st, hm, ik, eigenval, diff)
    
  case(OPTION__SUBSPACEDIAGONALIZATION__NONE)
    ! do nothing

  case default
    ASSERT(.false.)
    
  end select

  if(present(diff) .and. st%parallel_in_states) then
    call states_parallel_gather(st, diff)
  end if

  call profiling_out(diagon_prof)
  POP_SUB(X(subspace_diag))
end subroutine X(subspace_diag)

! ---------------------------------------------------------
!> This routine diagonalises the Hamiltonian in the subspace defined by the states.
subroutine X(subspace_diag_standard)(der, st, hm, ik, eigenval, diff)
  type(derivatives_t),    intent(in)    :: der
  type(states_t), target, intent(inout) :: st
  type(hamiltonian_t),    intent(in)    :: hm
  integer,                intent(in)    :: ik
  FLOAT,                  intent(out)   :: eigenval(:)
  FLOAT, optional,        intent(out)   :: diff(:)

  R_TYPE, allocatable :: hmss(:, :), rdiff(:)
  integer             :: ib, minst, maxst
  type(batch_t)       :: hpsib

  PUSH_SUB(X(subspace_diag_standard))

  SAFE_ALLOCATE(hmss(1:st%nst, 1:st%nst))
  
  call X(subspace_diag_hamiltonian)(der, st, hm, ik, hmss)
  
  ! Diagonalize the Hamiltonian in the subspace.
  ! only half of hmss has the matrix, but this is what Lapack needs
  call lalg_eigensolve(st%nst, hmss, eigenval)
  
#ifdef HAVE_MPI
  ! the eigenvectors are not unique due to phases and degenerate subspaces, but
  ! they must be consistent among processors in domain parallelization
  if(der%mesh%parallel_in_domains) &
      call MPI_Bcast(hmss, st%nst**2, R_MPITYPE, 0, der%mesh%mpi_grp%comm, mpi_err)
#endif

  ! Calculate the new eigenfunctions as a linear combination of the
  ! old ones.
  call states_rotate(der%mesh, st, hmss, ik)
  
  ! Recalculate the residues if requested by the diff argument.
  if(present(diff)) then 
    
    SAFE_ALLOCATE(rdiff(1:st%nst))
    
    do ib = st%group%block_start, st%group%block_end
      
      minst = states_block_min(st, ib)
      maxst = states_block_max(st, ib)

      call batch_copy(st%group%psib(ib, ik), hpsib)

      call X(hamiltonian_apply_batch)(hm, der, st%group%psib(ib, ik), hpsib, ik)
      call batch_axpy(der%mesh%np, -eigenval, st%group%psib(ib, ik), hpsib)
      call X(mesh_batch_dotp_vector)(der%mesh, hpsib, hpsib, rdiff(minst:maxst))

      call batch_end(hpsib, copy = .false.)

      diff(minst:maxst) = sqrt(abs(rdiff(minst:maxst)))

    end do

    SAFE_DEALLOCATE_A(rdiff)
    
  end if

  SAFE_DEALLOCATE_A(hmss)

  POP_SUB(X(subspace_diag_standard))

end subroutine X(subspace_diag_standard)

! --------------------------------------------------------- 
!> This routine diagonalises the Hamiltonian in the subspace defined by
!! the states; this version is aware of parallelization in states but
!! consumes more memory.
subroutine X(subspace_diag_scalapack)(der, st, hm, ik, eigenval, psi, diff)
  type(derivatives_t), intent(in)    :: der
  type(states_t),      intent(inout) :: st
  type(hamiltonian_t), intent(in)    :: hm
  integer,             intent(in)    :: ik
  FLOAT,               intent(out)   :: eigenval(:)
  R_TYPE,              intent(inout) :: psi(:, :, st%st_start:)
  FLOAT, optional,     intent(out)   :: diff(:)
 
#ifdef HAVE_SCALAPACK
  R_TYPE, allocatable  :: hs(:, :), hpsi(:, :, :), evectors(:, :), work(:)
  R_TYPE               :: rttmp
  integer              :: ist, lwork, size
  integer :: psi_block(1:2), total_np, psi_desc(BLACS_DLEN), hs_desc(BLACS_DLEN), info
  integer :: nbl, nrow, ncol, ip, idim
  type(batch_t) :: psib, hpsib
#ifdef R_TCOMPLEX
  integer :: lrwork
  CMPLX, allocatable :: rwork(:)
  CMPLX :: ftmp
#endif
  type(profile_t), save :: prof_diag, prof_gemm1, prof_gemm2
#ifdef HAVE_ELPA
  integer :: rcomm, ccomm
  logical :: elpa_success
#endif

  PUSH_SUB(X(subspace_diag_scalapack))

  SAFE_ALLOCATE(hpsi(1:der%mesh%np_part, 1:st%d%dim, st%st_start:st%st_end))
  
  call states_parallel_blacs_blocksize(st, der%mesh, psi_block, total_np)

  call descinit(psi_desc(1), total_np, st%nst, psi_block(1), psi_block(2), 0, 0,  st%dom_st_proc_grid%context, &
    st%d%dim*der%mesh%np_part, info)

  if(info /= 0) then
    write(message(1), '(a,i6)') "subspace diagonalization descinit for psi failed with error code ", info
    call messages_fatal(1)
  end if

  ! select the blocksize, we use the division used for state
  ! parallelization but with a maximum of 64
  nbl = min(64, psi_block(2))

  ! calculate the size of the matrix in each node
  nrow = max(1, numroc(st%nst, nbl, st%dom_st_proc_grid%myrow, 0, st%dom_st_proc_grid%nprow))
  ncol = max(1, numroc(st%nst, nbl, st%dom_st_proc_grid%mycol, 0, st%dom_st_proc_grid%npcol))

  SAFE_ALLOCATE(hs(1:nrow, 1:ncol))

  call descinit(hs_desc(1), st%nst, st%nst, nbl, nbl, 0, 0, st%dom_st_proc_grid%context, nrow, info)

  if(info /= 0) then
    write(message(1), '(a,i6)') "subspace diagonalization descinit for Hamiltonian failed with error code ", info
    call messages_fatal(1)
  end if

  ! calculate |hpsi> = H |psi>
  do ist = st%st_start, st%st_end, st%d%block_size
    size = min(st%d%block_size, st%st_end - ist + 1)
    
    call batch_init(psib, hm%d%dim, ist, ist + size - 1, psi(:, :, ist:))
    call batch_init(hpsib, hm%d%dim, ist, ist + size - 1, hpsi(: , :, ist:))
    
    call X(hamiltonian_apply_batch)(hm, der, psib, hpsib, ik)
    
    call batch_end(psib)
    call batch_end(hpsib)
  end do

  ! We need to set to zero some extra parts of the array
  if(st%d%dim == 1) then
    psi(der%mesh%np + 1:psi_block(1), 1:st%d%dim, st%st_start:st%st_end) = M_ZERO
    hpsi(der%mesh%np + 1:psi_block(1), 1:st%d%dim, st%st_start:st%st_end) = M_ZERO
  else
    psi(der%mesh%np + 1:der%mesh%np_part, 1:st%d%dim, st%st_start:st%st_end) = M_ZERO
    hpsi(der%mesh%np + 1:der%mesh%np_part, 1:st%d%dim, st%st_start:st%st_end) = M_ZERO
  end if
  
  call profiling_in(prof_gemm1, "SCALAPACK_GEMM1")

  ! get the matrix <psi|H|psi> = <psi|hpsi>
  call pblas_gemm('c', 'n', st%nst, st%nst, total_np, &
    R_TOTYPE(der%mesh%vol_pp(1)), psi(1, 1, st%st_start), 1, 1, psi_desc(1), &
    hpsi(1, 1, st%st_start), 1, 1, psi_desc(1), &
    R_TOTYPE(M_ZERO), hs(1, 1), 1, 1, hs_desc(1))

  SAFE_ALLOCATE(evectors(1:nrow, 1:ncol))
  call profiling_out(prof_gemm1)

  call profiling_in(prof_diag, "SCALAPACK_DIAG")

  ! now diagonalize
#ifdef R_TCOMPLEX

  call pzheev(jobz = 'V', uplo = 'U', n = st%nst, a = hs(1, 1) , ia = 1, ja = 1, desca = hs_desc(1), &
    w = eigenval(1), z = evectors(1, 1), iz = 1, jz = 1, descz = hs_desc(1), &
    work = rttmp, lwork = -1, rwork = ftmp, lrwork = -1, info = info)

  if(info /= 0) then
    write(message(1),'(a,i6)') "ScaLAPACK pzheev workspace query failure, error code = ", info
    call messages_fatal(1)
  end if

  lwork = nint(abs(rttmp))
  lrwork = nint(real(ftmp, 8))

  SAFE_ALLOCATE(work(1:lwork))
  SAFE_ALLOCATE(rwork(1:lrwork))

  call pzheev(jobz = 'V', uplo = 'U', n = st%nst, a = hs(1, 1) , ia = 1, ja = 1, desca = hs_desc(1), &
    w = eigenval(1), z = evectors(1, 1), iz = 1, jz = 1, descz = hs_desc(1), &
    work = work(1), lwork = lwork, rwork = rwork(1), lrwork = lrwork, info = info)

  if(info /= 0) then
    write(message(1),'(a,i6)') "ScaLAPACK pzheev call failure, error code = ", info
    call messages_fatal(1)
  end if

  SAFE_DEALLOCATE_A(work)
  SAFE_DEALLOCATE_A(rwork)

#else

#ifdef HAVE_ELPA
  
  mpi_err = get_elpa_communicators(st%dom_st_mpi_grp%comm, st%dom_st_proc_grid%myrow, st%dom_st_proc_grid%mycol, rcomm, ccomm)

  if(.false.) then

    elpa_success = solve_evp_real_1stage(na = st%nst, nev = st%nst, a = hs, &
      lda = ubound(hs, dim = 1), ev = eigenval, q = evectors, ldq = ubound(evectors, dim = 1), &
      nblk = nbl, matrixCols = ubound(hs, dim = 2), mpi_comm_rows = rcomm, mpi_comm_cols = ccomm)
  else
    
    elpa_success = solve_evp_real_2stage(na = st%nst, nev = st%nst, a = hs, &
      lda = ubound(hs, dim = 1), ev = eigenval, q = evectors, ldq = ubound(evectors, dim = 1), &
      nblk = nbl, matrixCols = ubound(hs, dim = 2), &
      mpi_comm_rows = rcomm, mpi_comm_cols = ccomm, mpi_comm_all = st%dom_st_mpi_grp%comm)

  end if
  
#else

  call pdsyev(jobz = 'V', uplo = 'U', n = st%nst, a = hs(1, 1) , ia = 1, ja = 1, desca = hs_desc(1), &
    w = eigenval(1), z = evectors(1, 1), iz = 1, jz = 1, descz = hs_desc(1), work = rttmp, lwork = -1, info = info)

  if(info /= 0) then
    write(message(1),'(a,i6)') "ScaLAPACK pdsyev workspace query failure, error code = ", info
    call messages_fatal(1)
  end if

  lwork = nint(abs(rttmp))
  SAFE_ALLOCATE(work(1:lwork))

  call pdsyev(jobz = 'V', uplo = 'U', n = st%nst, a = hs(1, 1) , ia = 1, ja = 1, desca = hs_desc(1), &
    w = eigenval(1), z = evectors(1, 1), iz = 1, jz = 1, descz = hs_desc(1), work = work(1), lwork = lwork, info = info)

  if(info /= 0) then
    write(message(1),'(a,i6)') "ScaLAPACK pdsyev call failure, error code = ", info
    call messages_fatal(1)
  end if
  
  SAFE_DEALLOCATE_A(work)
#endif
  
#endif

  call profiling_out(prof_diag)

  SAFE_DEALLOCATE_A(hs)

  !$omp parallel private(ist, idim, ip)
  do ist = st%st_start, st%st_end
    do idim = 1, st%d%dim
      !$omp do
      do ip = 1, der%mesh%np
        hpsi(ip, idim, ist) = psi(ip, idim, ist)
      end do
      !$omp end do nowait
    end do
  end do
  !$omp end parallel

  call profiling_in(prof_gemm2, "SCALAPACK_GEMM2")
  call pblas_gemm('n', 'n', total_np, st%nst, st%nst, &
    R_TOTYPE(M_ONE), hpsi(1, 1, st%st_start), 1, 1, psi_desc(1), &
    evectors(1, 1), 1, 1, hs_desc(1), &
    R_TOTYPE(M_ZERO), psi(1, 1, st%st_start), 1, 1, psi_desc(1))
  call profiling_out(prof_gemm2)

  ! Recalculate the residues if requested by the diff argument.
  if(present(diff)) then 
    do ist = st%st_start, st%st_end
      call X(hamiltonian_apply)(hm, der, psi(:, :, ist) , hpsi(:, :, st%st_start), ist, ik)
      diff(ist) = X(states_residue)(der%mesh, st%d%dim, hpsi(:, :, st%st_start), eigenval(ist), psi(:, :, ist))
    end do
  end if
  
  SAFE_DEALLOCATE_A(hpsi)
  SAFE_DEALLOCATE_A(hs)
  
  POP_SUB(X(subspace_diag_scalapack))

#endif /* SCALAPACK */  
end subroutine X(subspace_diag_scalapack)

! ------------------------------------------------------

!> This routine diagonalises the Hamiltonian in the subspace defined by the states.
subroutine X(subspace_diag_hamiltonian)(der, st, hm, ik, hmss)
  type(derivatives_t),    intent(in)    :: der
  type(states_t), target, intent(inout) :: st
  type(hamiltonian_t),    intent(in)    :: hm
  integer,                intent(in)    :: ik
  R_TYPE,                 intent(out)   :: hmss(:, :)

  integer       :: ib, jb, ip
  R_TYPE, allocatable :: psi(:, :, :), hpsi(:, :, :)
  type(batch_t), allocatable :: hpsib(:)
  integer :: sp, ep, size, block_size, ierr
  type(accel_mem_t) :: psi_buffer, hpsi_buffer, hmss_buffer

  PUSH_SUB(X(subspace_diag_hamiltonian))
  call profiling_in(hamiltonian_prof, "SUBSPACE_HAMILTONIAN")

  SAFE_ALLOCATE(hpsib(st%group%block_start:st%group%block_end))
  
  do ib = st%group%block_start, st%group%block_end
    call batch_copy(st%group%psib(ib, ik), hpsib(ib))
    call X(hamiltonian_apply_batch)(hm, der, st%group%psib(ib, ik), hpsib(ib), ik)
  end do
  
  if(states_are_packed(st) .and. accel_is_enabled()) then

    ASSERT(ubound(hmss, dim = 1) == st%nst)

    call accel_create_buffer(hmss_buffer, ACCEL_MEM_READ_WRITE, R_TYPE_VAL, st%nst*st%nst)
    call accel_set_buffer_to_zero(hmss_buffer, R_TYPE_VAL, st%nst*st%nst)

    if(.not. st%parallel_in_states .and. st%group%block_start == st%group%block_end) then
      ! all the states are stored in one block
      ! we can use blas directly

      call X(accel_gemm)(transA = ACCEL_BLAS_N, transB = ACCEL_BLAS_C, &
        M = int(st%nst, 8), N = int(st%nst, 8), K = int(der%mesh%np, 8), &
        alpha = R_TOTYPE(der%mesh%volume_element), &
        A = st%group%psib(st%group%block_start, ik)%pack%buffer, offA = 0_8, &
        lda = int(st%group%psib(st%group%block_start, ik)%pack%size(1), 8), &
        B = hpsib(st%group%block_start)%pack%buffer, offB = 0_8, &
        ldb = int(hpsib(st%group%block_start)%pack%size(1), 8), &
        beta = R_TOTYPE(CNST(0.0)), &
        C = hmss_buffer, offC = 0_8, ldc = int(st%nst, 8))

    else

      ASSERT(.not. st%parallel_in_states)
      
      ! we have to copy the blocks to a temporary array
      block_size = batch_points_block_size(st%group%psib(st%group%block_start, ik))

      call accel_create_buffer(psi_buffer, ACCEL_MEM_READ_WRITE, R_TYPE_VAL, st%nst*block_size)
      call accel_create_buffer(hpsi_buffer, ACCEL_MEM_READ_WRITE, R_TYPE_VAL, st%nst*block_size)

      do sp = 1, der%mesh%np, block_size
        size = min(block_size, der%mesh%np - sp + 1)

        do ib = st%group%block_start, st%group%block_end
          ASSERT(R_TYPE_VAL == batch_type(st%group%psib(ib, ik)))
          call batch_get_points(st%group%psib(ib, ik), sp, sp + size - 1, psi_buffer, st%nst)
          call batch_get_points(hpsib(ib), sp, sp + size - 1, hpsi_buffer, st%nst)
        end do

        call X(accel_gemm)(transA = ACCEL_BLAS_N, transB = ACCEL_BLAS_C, &
          M = int(st%nst, 8), N = int(st%nst, 8), K = int(size, 8), &
          alpha = R_TOTYPE(der%mesh%volume_element), &
          A = psi_buffer, offA = 0_8, lda = int(st%nst, 8), &
          B = hpsi_buffer, offB = 0_8, ldb = int(st%nst, 8), beta = R_TOTYPE(CNST(1.0)), & 
          C = hmss_buffer, offC = 0_8, ldc = int(st%nst, 8))
        
        call accel_finish()

      end do


      call accel_release_buffer(psi_buffer)
      call accel_release_buffer(hpsi_buffer)
      
    end if

    call accel_read_buffer(hmss_buffer, st%nst*st%nst, hmss)
    call accel_release_buffer(hmss_buffer)

  else

#ifdef R_TREAL  
    block_size = max(40, hardware%l2%size/(2*8*st%nst))
#else
    block_size = max(20, hardware%l2%size/(2*16*st%nst))
#endif

    hmss(1:st%nst, 1:st%nst) = CNST(0.0)
    
    SAFE_ALLOCATE(psi(1:st%nst, 1:st%d%dim, 1:block_size))
    SAFE_ALLOCATE(hpsi(1:st%nst, 1:st%d%dim, 1:block_size))

    do sp = 1, der%mesh%np, block_size
      size = min(block_size, der%mesh%np - sp + 1)
      
      do ib = st%group%block_start, st%group%block_end
        call batch_get_points(st%group%psib(ib, ik), sp, sp + size - 1, psi)
        call batch_get_points(hpsib(ib), sp, sp + size - 1, hpsi)
      end do

      if(st%parallel_in_states) then
        call states_parallel_gather(st, (/st%d%dim, size/), psi)
        call states_parallel_gather(st, (/st%d%dim, size/), hpsi)
      end if
      
      if(der%mesh%use_curvilinear) then
        do ip = 1, size
          psi(1:st%nst, 1:st%d%dim, ip) = psi(1:st%nst, 1:st%d%dim, ip)*der%mesh%vol_pp(sp + ip - 1)
        end do
      end if

      call blas_gemm(transa = 'n', transb = 'c',        &
        m = st%nst, n = st%nst, k = size*st%d%dim,      &
        alpha = R_TOTYPE(der%mesh%volume_element),      &
        a = hpsi(1, 1, 1), lda = ubound(hpsi, dim = 1),   &
        b = psi(1, 1, 1), ldb = ubound(psi, dim = 1), &
        beta = R_TOTYPE(CNST(1.0)),                     & 
        c = hmss(1, 1), ldc = ubound(hmss, dim = 1))
    end do

#ifdef R_TCOMPLEX
    hmss(1:st%nst, 1:st%nst) = R_CONJ(hmss(1:st%nst, 1:st%nst))
#endif

  end if
  
  call profiling_count_operations((R_ADD + R_MUL)*st%nst*(st%nst - CNST(1.0))*der%mesh%np)
  
  do ib = st%group%block_start, st%group%block_end
    call batch_end(hpsib(ib), copy = .false.)
  end do
  
  SAFE_DEALLOCATE_A(hpsib)
    
  if(der%mesh%parallel_in_domains) call comm_allreduce(der%mesh%mpi_grp%comm, hmss, dim = (/st%nst, st%nst/))
  
  call profiling_out(hamiltonian_prof)
  POP_SUB(X(subspace_diag_hamiltonian))

end subroutine X(subspace_diag_hamiltonian)


!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
