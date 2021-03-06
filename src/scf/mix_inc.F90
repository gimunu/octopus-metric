!! Copyright (C) 2002-2015 M. Marques, A. Castro, A. Rubio, G. Bertsch, X. Andrade
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
!! $Id: mix_inc.F90 15523 2016-07-24 23:22:19Z xavier $

! ---------------------------------------------------------
subroutine X(mixing)(smix, vin, vout, vnew)
  type(mix_t),  intent(inout) :: smix
  R_TYPE,       intent(in)    :: vin(:, :, :), vout(:, :, :)
  R_TYPE,       intent(out)   :: vnew(:, :, :)
  
  PUSH_SUB(X(mixing))

  ASSERT(associated(smix%der))
  
  smix%iter = smix%iter + 1
  
  select case (smix%scheme)
  case (OPTION__MIXINGSCHEME__LINEAR)
    call X(mixing_linear)(smix%coeff, smix%d1, smix%d2, smix%d3, vin, vout, vnew)
    
  case (OPTION__MIXINGSCHEME__BROYDEN)
    call X(mixing_broyden)(smix, vin, vout, vnew, smix%iter)
    
  case (OPTION__MIXINGSCHEME__DIIS)
    call X(mixing_diis)(smix, vin, vout, vnew, smix%iter)

  case (OPTION__MIXINGSCHEME__BOWLER_GILLAN)
    call X(mixing_grpulay)(smix, vin, vout, vnew, smix%iter)
    
  end select
  
  POP_SUB(X(mixing))
end subroutine X(mixing)


! ---------------------------------------------------------
subroutine X(mixing_linear)(coeff, d1, d2, d3, vin, vout, vnew)
  FLOAT,        intent(in) :: coeff
  integer,      intent(in) :: d1, d2, d3
  R_TYPE,       intent(in) :: vin(:, :, :), vout(:, :, :)
  R_TYPE,       intent(out):: vnew(:, :, :)

  PUSH_SUB(X(mixing_linear))
  
  vnew(1:d1, 1:d2, 1:d3) = vin(1:d1, 1:d2, 1:d3)*(M_ONE - coeff) + coeff*vout(1:d1, 1:d2, 1:d3)
  
  POP_SUB(X(mixing_linear))
end subroutine X(mixing_linear)


! ---------------------------------------------------------
subroutine X(mixing_broyden)(smix, vin, vout, vnew, iter)
  type(mix_t),    intent(inout) :: smix
  R_TYPE,         intent(in)    :: vin(:, :, :), vout(:, :, :)
  R_TYPE,         intent(out)   :: vnew(:, :, :)
  integer,        intent(in)    :: iter

  integer :: ipos, iter_used, i, j, d1, d2, d3
  R_TYPE :: gamma
  R_TYPE, allocatable :: f(:, :, :)

  PUSH_SUB(X(mixing_broyden))

  d1 = smix%d1
  d2 = smix%d2
  d3 = smix%d3

  SAFE_ALLOCATE(f(1:d1, 1:d2, 1:d3))
  
  f(1:d1, 1:d2, 1:d3) = vout(1:d1, 1:d2, 1:d3) - vin(1:d1, 1:d2, 1:d3)
  if(iter > 1) then
    ! Store df and dv from current iteration
    ipos = mod(smix%last_ipos, smix%ns) + 1
    
    call lalg_copy(d1, d2, d3, f(:, :, :), smix%X(df)(:, :, :, ipos))
    call lalg_copy(d1, d2, d3, vin(:, :, :), smix%X(dv)(:, :, :, ipos))
    call lalg_axpy(d1, d2, d3, R_TOTYPE(-M_ONE), smix%X(f_old)(:, :, :),   smix%X(df)(:, :, :, ipos))
    call lalg_axpy(d1, d2, d3, R_TOTYPE(-M_ONE), smix%X(vin_old)(:, :, :), smix%X(dv)(:, :, :, ipos))
    
    gamma = M_ZERO
    do i = 1, d2
      do j = 1, d3
        gamma = gamma + X(mix_dotp)(smix, smix%X(df)(:, i, j, ipos), smix%X(df)(:, i, j, ipos))
      end do
    end do
    gamma = sqrt(gamma)
    
    if(abs(gamma) > CNST(1e-8)) then
      gamma = M_ONE/gamma
    else
      gamma = M_ONE
    end if
    call lalg_scal(d1, d2, d3, gamma, smix%X(df)(:, :, :, ipos))
    call lalg_scal(d1, d2, d3, gamma, smix%X(dv)(:, :, :, ipos))
    
    smix%last_ipos = ipos
  end if
  
  ! Store residual and vin for next iteration
  smix%X(vin_old)(1:d1, 1:d2, 1:d3) = vin(1:d1, 1:d2, 1:d3)
  smix%X(f_old)  (1:d1, 1:d2, 1:d3) = f  (1:d1, 1:d2, 1:d3)
  
  ! extrapolate new vector
  iter_used = min(iter -1, smix%ns)
  call X(broyden_extrapolation)(smix, smix%coeff, d1, d2, d3, vin, vnew, iter_used, f, smix%X(df), smix%X(dv))

  SAFE_DEALLOCATE_A(f)

  POP_SUB(X(mixing_broyden))
end subroutine X(mixing_broyden)


! ---------------------------------------------------------
subroutine X(broyden_extrapolation)(this, coeff, d1, d2, d3, vin, vnew, iter_used, f, df, dv)
  type(mix_t), intent(inout) :: this
  FLOAT,       intent(in)    :: coeff
  integer,     intent(in)    :: d1, d2, d3, iter_used
  R_TYPE,      intent(in)    :: vin(:, :, :), f(:, :, :)
  R_TYPE,      intent(in)    :: df(:, :, :, :), dv(:, :, :, :)
  R_TYPE,      intent(out)   :: vnew(:, :, :)
  
  FLOAT, parameter :: w0 = CNST(0.01), ww = M_FIVE
  integer  :: i, j, k, l
  R_TYPE    :: gamma, determinant
  R_TYPE, allocatable :: beta(:, :), work(:)

  PUSH_SUB(X(broyden_extrapolation))
  
  if (iter_used == 0) then
    ! linear mixing...
    vnew(1:d1, 1:d2, 1:d3) = vin(1:d1, 1:d2, 1:d3) + coeff*f(1:d1, 1:d2, 1:d3)
    POP_SUB(X(broyden_extrapolation))
    return
  end if
  
  SAFE_ALLOCATE(beta(1:iter_used, 1:iter_used))
  SAFE_ALLOCATE(work(1:iter_used))
  
  ! compute matrix beta, Johnson eq. 13a
  beta = M_ZERO
  do i = 1, iter_used
    do j = i + 1, iter_used
      beta(i, j) = M_ZERO
      do k = 1, d2
        do l = 1, d3
          beta(i, j) = beta(i, j) + ww*ww*X(mix_dotp)(this, df(:, k, l, j), df(:, k, l, i))
        end do
      end do
      beta(j, i) = R_CONJ(beta(i, j))
    end do
    beta(i, i) = w0**2 + ww**2
  end do
  
  ! invert matrix beta
  determinant = lalg_inverter(iter_used, beta)
  
  do i = 1, iter_used
    work(i) = M_ZERO
    do k = 1, d2
      do l = 1, d3
        work(i) = work(i) + X(mix_dotp)(this, df(:, k, l, i), f(:, k, l))
      end do
    end do
  end do

  ! linear mixing term
  vnew(1:d1, 1:d2, 1:d3) = vin(1:d1, 1:d2, 1:d3) + coeff*f(1:d1, 1:d2, 1:d3)
  
  ! other terms
  do i = 1, iter_used
    gamma = ww*sum(beta(:, i)*work(:))
    vnew(1:d1, 1:d2, 1:d3) = vnew(1:d1, 1:d2, 1:d3) - ww*gamma*(coeff*df(1:d1, 1:d2, 1:d3, i) + dv(1:d1, 1:d2, 1:d3, i))
  end do
  
  SAFE_DEALLOCATE_A(beta)
  SAFE_DEALLOCATE_A(work)
  
  POP_SUB(X(broyden_extrapolation))
end subroutine X(broyden_extrapolation)

!--------------------------------------------------------------------

subroutine X(mixing_diis)(this, vin, vout, vnew, iter)
  type(mix_t), intent(inout) :: this
  R_TYPE,      intent(in)    :: vin(:, :, :)
  R_TYPE,      intent(in)    :: vout(:, :, :)
  R_TYPE,      intent(out)   :: vnew(:, :, :)
  integer,     intent(in)    :: iter

  integer :: size, ii, jj, kk, ll
  FLOAT :: sumalpha
  R_TYPE, allocatable :: aa(:, :), alpha(:), rhs(:)

  PUSH_SUB(X(mixing_diis))

  if(iter <= this%d4) then

    size = iter
    
  else

    size = this%d4

    do ii = 2, size
      call lalg_copy(this%d1, this%d2, this%d3, this%X(dv)(:, :, :, ii), this%X(dv)(:, :, :, ii - 1))
      call lalg_copy(this%d1, this%d2, this%d3, this%X(df)(:, :, :, ii), this%X(df)(:, :, :, ii - 1))
    end do
    
  end if

  call lalg_copy(this%d1, this%d2, this%d3, vin, this%X(dv)(:, :, :, size))
  this%X(df)(1:this%d1, 1:this%d2, 1:this%d3, size) = vout(1:this%d1, 1:this%d2, 1:this%d3) - vin(1:this%d1, 1:this%d2, 1:this%d3)

  if(iter == 1 .or. mod(iter, this%interval) /= 0) then

    vnew(1:this%d1, 1:this%d2, 1:this%d3) = (CNST(1.0) - this%coeff)*vin(1:this%d1, 1:this%d2, 1:this%d3) &
      + this%coeff*vout(1:this%d1, 1:this%d2, 1:this%d3)

    POP_SUB(X(mixing_diis))
    return
  end if
 

  SAFE_ALLOCATE(aa(1:size + 1, 1:size + 1))
  SAFE_ALLOCATE(alpha(1:size + 1))
  SAFE_ALLOCATE(rhs(1:size + 1))

  do ii = 1, size
    do jj = 1, size

      aa(ii, jj) = CNST(0.0)
      do kk = 1, this%d2
        do ll = 1, this%d3
          aa(ii, jj) = aa(ii, jj) + X(mix_dotp)(this, this%X(df)(:, kk, ll, jj), this%X(df)(:, kk, ll, ii))
        end do
      end do
      
    end do
  end do

  aa(1:size, size + 1) = CNST(-1.0)
  aa(size + 1, 1:size) = CNST(-1.0)
  aa(size + 1, size + 1) = CNST(0.0)
  
  rhs(1:size) = CNST(0.0)
  rhs(size + 1) = CNST(-1.0)

  call lalg_least_squares(size + 1, aa, rhs, alpha)

  sumalpha = sum(alpha(1:size))
  alpha = alpha/sumalpha
  
  vnew(1:this%d1, 1:this%d2, 1:this%d3) = CNST(0.0)
  
  do ii = 1, size
    vnew(1:this%d1, 1:this%d2, 1:this%d3) = vnew(1:this%d1, 1:this%d2, 1:this%d3) &
      + alpha(ii)*(this%X(dv)(1:this%d1, 1:this%d2, 1:this%d3, ii) &
      + this%residual_coeff*this%X(df)(1:this%d1, 1:this%d2, 1:this%d3, ii))
  end do

  POP_SUB(X(mixing_diis))
end subroutine X(mixing_diis)

! ---------------------------------------------------------
! Guaranteed-reduction Pulay
! ---------------------------------------------------------
subroutine X(mixing_grpulay)(smix, vin, vout, vnew, iter)
  type(mix_t), intent(inout) :: smix
  integer,      intent(in)   :: iter
  R_TYPE,        intent(in)   :: vin(:, :, :), vout(:, :, :)
  R_TYPE,        intent(out)  :: vnew(:, :, :)
  
  integer :: d1, d2, d3
  integer :: ipos, iter_used
  R_TYPE, allocatable :: f(:, :, :)
    
  PUSH_SUB(X(mixing_grpulay))

  d1 = smix%d1
  d2 = smix%d2
  d3 = smix%d3
  
  SAFE_ALLOCATE(f(1:d1, 1:d2, 1:d3))
  f(1:d1, 1:d2, 1:d3) = vout(1:d1, 1:d2, 1:d3) - vin(1:d1, 1:d2, 1:d3)

  ! we only extrapolate a new vector every two iterations
  select case (mod(iter, 2))
  case (1)
    ! Store df and dv from current iteration
    if (iter > 1) then
      ipos = smix%last_ipos
      call lalg_copy(d1, d2, d3, f(:, :, :), smix%X(df)(:, :, :, ipos))
      call lalg_copy(d1, d2, d3, vin(:, :, :), smix%X(dv)(:, :, :, ipos))
      call lalg_axpy(d1, d2, d3, R_TOTYPE(-M_ONE), smix%X(f_old)(:, :, :), smix%X(df)(:, :, :, ipos))
      call lalg_axpy(d1, d2, d3, R_TOTYPE(-M_ONE), smix%X(vin_old)(:, :, :), smix%X(dv)(:, :, :, ipos))
    end if
    
    ! Store residual and vin for next extrapolation
    smix%X(vin_old) = vin
    smix%X(f_old) = f
    
    ! we need the output vector for vout. So let`s do vnew = vout to get that information
    vnew = vout
  case (0)
    ! Store df and dv from current iteration in arrays df and dv so that we can use them
    ! for the extrapolation. Next iterations they will be lost.
    ipos = mod(smix%last_ipos, smix%ns + 1) + 1
    call lalg_copy(d1, d2, d3, f(:, :, :), smix%X(df)(:, :, :, ipos))
    call lalg_copy(d1, d2, d3, vin(:, :, :), smix%X(dv)(:, :, :, ipos))
    call lalg_axpy(d1, d2, d3, R_TOTYPE(-M_ONE), smix%X(f_old)(:, :, :), smix%X(df)(:, :, :, ipos))
    call lalg_axpy(d1, d2, d3, R_TOTYPE(-M_ONE), smix%X(vin_old)(:, :, :), smix%X(dv)(:, :, :, ipos))
    
    smix%last_ipos = ipos

    ! extrapolate new vector
    iter_used = min(iter/2, smix%ns + 1)
    call X(pulay_extrapolation)(smix, d2, d3, vin, vout, vnew, iter_used, f, &
         smix%X(df)(1:d1, 1:d2, 1:d3, 1:iter_used), smix%X(dv)(1:d1, 1:d2, 1:d3, 1:iter_used))

  end select

  SAFE_DEALLOCATE_A(f)
  
  POP_SUB(X(mixing_grpulay))
end subroutine X(mixing_grpulay)


! ---------------------------------------------------------
subroutine X(pulay_extrapolation)(this, d2, d3, vin, vout, vnew, iter_used, f, df, dv)
  type(mix_t), intent(in) :: this
  integer, intent(in) :: d2, d3
  integer, intent(in)   :: iter_used
  R_TYPE,  intent(in)  :: vin(:, :, :), vout(:, :, :), f(:, :, :), df(:, :, :, :), dv(:, :, :, :)
  R_TYPE,  intent(out) :: vnew(:, :, :)
  
  integer :: i, j, k, l
  R_TYPE :: alpha, determinant
  R_TYPE, allocatable :: a(:, :)
  
  PUSH_SUB(X(pulay_extrapolation))
  
  SAFE_ALLOCATE(a(1:iter_used, 1:iter_used))
  
  ! set matrix A
  a = M_ZERO
  do i = 1, iter_used
    do j = i, iter_used
      a(i, j) = M_ZERO
      do k = 1, d2
        do l = 1, d3
          a(i, j) = a(i, j) + X(mix_dotp)(this, df(:, k, l, j), df(:, k, l, i))
        end do
      end do
      if(j > i) a(j, i) = a(i, j)
    end do
  end do
  if (all(abs(a) < 1.0E-8)) then
    ! residuals are too small. Do not mix.
    vnew = vout
    POP_SUB(X(pulay_extrapolation))
    return
  end if
  
  determinant = lalg_inverter(iter_used, a)
  
  ! compute new vector
  vnew = vin
  do i = 1, iter_used
    alpha = M_ZERO
    do j = 1, iter_used
      do k = 1, d2
        do l = 1, d3
          alpha = alpha - a(i, j)*X(mix_dotp)(this, df(:, k, l, j), f(:, k, l))
        end do
      end do
    end do
    vnew(:, :, :) = vnew(:, :, :) + alpha * dv(:, :, :, i)
  end do

  SAFE_DEALLOCATE_A(a)
  
  POP_SUB(X(pulay_extrapolation))
end subroutine X(pulay_extrapolation)

! --------------------------------------------------------------

R_TYPE function X(mix_dotp)(this, xx, yy) result(dotp)
  type(mix_t), intent(in) :: this
  R_TYPE,      intent(in) :: xx(:)
  R_TYPE,      intent(in) :: yy(:)

  R_TYPE, allocatable :: ff(:), precff(:)
  
  PUSH_SUB(X(mix_dotp))

  ASSERT(this%d1 == this%der%mesh%np)
  
  if(this%precondition) then

    SAFE_ALLOCATE(ff(1:this%der%mesh%np_part))
    SAFE_ALLOCATE(precff(1:this%der%mesh%np))

    ff(1:this%der%mesh%np) = yy(1:this%der%mesh%np)
    call X(derivatives_perform)(this%preconditioner, this%der, ff, precff)
    dotp = X(mf_dotp)(this%der%mesh, xx, precff)

    SAFE_DEALLOCATE_A(precff)
    SAFE_DEALLOCATE_A(ff)
      
  else
    dotp = X(mf_dotp)(this%der%mesh, xx, yy)
  end if

  POP_SUB(X(mix_dotp))
  
end function X(mix_dotp)

!! Local Variables:
!! mode: f90
!! coding: utf-8
!! End:
