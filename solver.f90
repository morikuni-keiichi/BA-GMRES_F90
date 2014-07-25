module solver 
	use func
	use globvar
	implicit none
	private
	public :: BAGMRES
contains
	subroutine BAGMRES(Iter, Riter, RelRes, x, t_cri)
	
	real(dp) H(omax+1, omax), V(n, omax+1)
	real(dp), intent(out) :: RelRes(:), x(:)
	real(dp) c(omax), g(omax+1), r(m), s(omax), w(n), x0(n), y(omax)
	real(dp) :: beta, deps = 2.0d-52, inprod, tmp, Tol
	integer, intent(out) :: Iter, Riter
	integer :: bd = 0, i, iter_tot = 1, j, k, k1, k2, l, p
	real(dp) :: t0, t1, t2, t_cri

	call cpu_time(t0)

!	The initial approximate solution is equal to zero
	x0(1:n) = zero

! The 2-norm of a_j, j=1,...,n, required for NR-SOR
	do j = 1, n
		inprod = zero
		do l = jp(j), jp(j+1)-1
			inprod = inprod + AC(l)*AC(l)
		enddo
		if (inprod /= zero) then
			Aei(j) = one / inprod 
		else
			write(*, *) 'warning: ||aj|| = 0.0, j =', j
			stop
		endif
	enddo

! Tol = cri_res * ||A^T b||_2
	call cpu_time(t1)
		w(1:n) = zero
		do j = 1, n
			k1 = jp(j)
			k2 = jp(j+1)-1
			w(j) = sum(AC(k1:k2)*b(ia(k1:k2)))
		enddo
		Tol = cri_res * nrm2(w(1:n), n)
	call cpu_time(t2)
	t_cri = t2 - t1
	
	do p = 0, rmax
		
		r(1:m) = zero
		do j = 1, n
			tmp = x0(j)
			do l = jp(j), jp(j+1)-1
				i = ia(l)
				r(i) = r(i) + tmp*AC(l)
			enddo
		enddo
	
	! r0 = b - A*x0
		r(1:m) = b(1:m) - r(1:m)

		if (at > 0) then
			write(*, *) 'Automatic NR-SOR inner-iteration parameter tuning'
			call atNRSOR(r(1:m), w(1:n))
			write(*, *) 'Tuned'
		else if (at == 0) then
		! NR-SOR inner-iteration preconditioning without automatic parameter tuning 
			call NRSOR(r(1:m), w(1:n))
		endif

		beta = nrm2(w(1:n), n)

	! Normalization of the vector v_1
		tmp = one / beta
		V(1:n, 1) = tmp * w(1:n)
	
		g(1) = beta
	
		do k = 1, omax 
	
			r(1:m) = zero
			do j = 1, n
				tmp = V(j, k)
				do l = jp(j), jp(j+1)-1
					i = ia(l)
					r(i) = r(i) + tmp*AC(l)
				enddo
			enddo

		! NR-SOR inner-iteration preconditioning
			call NRSOR(r(1:m), w(1:n))

		! Modified Gram-Schmidt orthogonalization
			do i = 1, k
				H(i, k) = sum(w(1:n) * V(1:n, i))
				w(1:n) = w(1:n) - H(i, k)*V(1:n, i)
			enddo
			
			H(k+1, k) = nrm2(w(1:n), n) 
		
			if (H(k+1, k) > deps) then
			! Normalization of the vector v_{k+1}
				tmp = one / H(k+1, k)
				V(1:n, k+1) = tmp * w(1:n)
			else
				write(*, *) 'BREAKDOW at step', k
				write(*, *) 'h_{k+1, k} =', H(k+1, k)
				bd = 1
			endif
	
		! Application of Givens rotations
			do i = 1, k-1
				tmp =  c(i)*H(i, k) + s(i)*H(i+1, k)
				H(i+1, k) = -s(i)*H(i, k) + c(i)*H(i+1, k)
				H(i, k) = tmp
			enddo

		! Construction of Givens rotations
			call rotg(H(k, k), H(k+1, k), c(k), s(k))

			g(k+1) = -s(k)*g(k)
			g(k) = c(k)*g(k)
	
	!---------------------------- 
		!	Derivation of the approximate solution x_k	
			call cpu_time(t1)
		!	Backward substitution
			H(k, k) = one / H(k, k)
			y(k) = g(k) * H(k, k)
			do i = k-1, 1, -1
				y(i) = (g(i) - sum(H(i, i+1:k) * y(i+1:k))) * H(i, i)
			enddo
	
			x(1:n) = matmul(V(1:n, 1:k), y(1:k))
	
			x(1:n) = x0(1:n) + x(1:n)

			r(1:m) = zero
			do j = 1, n
				tmp = x(j)
				do l = jp(j), jp(j+1)-1
					i = ia(l)
					r(i) = r(i) + tmp*AC(l)
				enddo
			enddo
			
		! r_k = b - A*x_k
			r(1:m) = b(1:m) - r(1:m)
		
		! w = A^T r
			do j = 1, n
				k1 = jp(j)
				k2 = jp(j+1)-1
				w(j) = sum(AC(k1:k2) * r(ia(k1:k2)))
			enddo
	
			RelRes(iter_tot) = nrm2(w(1:n), n)
			
			call cpu_time(t2)
			t_cri = t_cri + t2 - t1
		!--------------------------
			
		!	Convergence check
			if (RelRes(iter_tot) < Tol .or. (k == omax .and. p==rmax) .or. bd == 1) then	
				
				y(k) = g(k) * H(k, k)
				do i = k-1, 1, -1
					y(i) = (g(i) - sum(H(i, i+1:k) * y(i+1:k))) * H(i, i)
				enddo
		
				x(1:n) = matmul(V(1:n, 1:k), y(1:k))

				x(1:n) = x0(1:n) + x(1:n)

				Iter = iter_tot
				Riter = p

				return

			endif

			iter_tot = iter_tot + 1

		enddo

		x0(1:n) = x(1:n)

	enddo

	end subroutine BAGMRES

	subroutine NRSOR(rhs, x)

	real(dp), intent(out) :: x(:)
	real(dp), intent(inout) :: rhs(:)
	real(dp) d
	integer i, j, k, k1, k2, l

	x(1:n) = zero	

	do k = 1, nin 
		do j = 1, n
			k1 = jp(j)
			k2 = jp(j+1)-1
			d = omg * sum(rhs(ia(k1:k2))*AC(k1:k2)) * Aei(j)
			x(j) = x(j) + d
			if (k == nin .and. j == n) return
			do l = k1, k2
				i = ia(l)
				rhs(i) = rhs(i) - d*AC(l)
			enddo
		enddo
	enddo
		
	end subroutine NRSOR

	subroutine atNRSOR(rhs, x)
	
	real(dp), intent(inout) :: rhs(:)
	real(dp), intent(out) :: x(:)
	real(dp) :: d, e, res1, res2 = zero, y(n), tmprhs(m)
	integer i, ii, j, k, k1, k2, l

	tmprhs(1:m) = rhs(1:m)
	
	omg = one 

	x(1:n) = zero
	y(1:n) = zero

	do i = 1, 100

		do j = 1, n
			k1 = jp(j)
			k2 = jp(j+1)-1
			d = omg * sum(rhs(ia(k1:k2))*AC(k1:k2)) * Aei(j)
			x(j) = x(j) + d
			do l = k1, k2
				ii = ia(l)
				rhs(ii) = rhs(ii) - d*AC(l)
			enddo
		enddo
		
		d = maxval(abs(x(1:n)))
		e = maxval(abs(x(1:n) - y(1:n))) 
 
		if (e < 1.0d+1 ** (-one) * d .or. i == 100) then
			nin = i
			exit
		endif

		y(1:n) = x(1:n)
	
	enddo

	do k = 19, 1, -1
		
		omg = 1.0d-1 * dble(k)
	
		rhs(1:m) = tmprhs(1:m)

		x(1:n) = zero

		do i = 1, nin 
			do j = 1, n
				k1 = jp(j)
				k2 = jp(j+1)-1
				d = omg * sum(rhs(ia(k1:k2))*AC(k1:k2)) * Aei(j)
				x(j) = x(j) + d
				do l = k1, k2
					ii = ia(l)
					rhs(ii) = rhs(ii) - d*AC(l)
				enddo
			enddo
		enddo

		res1 = nrm2(rhs(1:m), m)

		if (k < 19) then
			if (res1 > res2) then
				omg = omg + 1.0d-1
				x(1:n) = y(1:n)
				return
			else if (k == 1) then
				omg = 0.1d0
				return
			endif
		endif

		res2 = res1

		y(1:n) = x(1:n)

	enddo

	end subroutine atNRSOR

end module solver 
