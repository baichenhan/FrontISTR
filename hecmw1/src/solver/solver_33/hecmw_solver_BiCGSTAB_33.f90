!======================================================================!
!                                                                      !
!   Software Name : HEC-MW Library for PC-cluster                      !
!         Version : 2.5                                                !
!                                                                      !
!     Last Update : 2006/06/01                                         !
!        Category : Linear Solver                                      !
!                                                                      !
!            Written by Kengo Nakajima (Univ. of Tokyo)                !
!                                                                      !
!     Contact address :  IIS,The University of Tokyo RSS21 project     !
!                                                                      !
!     "Structural Analysis System for General-purpose Coupling         !
!      Simulations Using High End Computing Middleware (HEC-MW)"       !
!                                                                      !
!======================================================================!

!C
!C***
!C*** module hecmw_solver_BiCGSTAB_33
!C***
!C
      module hecmw_solver_BiCGSTAB_33
      contains
!C
!C*** BiCGSTAB_3
!C
      subroutine hecmw_solve_BiCGSTAB_33( hecMESH,  hecMAT, ITER, RESID, ERROR, &
     &                                    Tset, Tsol, Tcomm )

      use hecmw_util
      use m_hecmw_solve_error
      use m_hecmw_comm_f
      use hecmw_matrix_misc
      use hecmw_solver_misc
      use hecmw_solver_misc_33

      implicit none

      type(hecmwST_local_mesh) :: hecMESH
      type(hecmwST_matrix) :: hecMAT
      integer(kind=kint ), intent(inout):: ITER, ERROR
      real   (kind=kreal), intent(inout):: RESID, Tset, Tsol, Tcomm

      integer(kind=kint ) :: my_rank
      integer(kind=kint ) :: ITERlog, TIMElog
      real(kind=kreal), pointer :: B(:), X(:)

      real(kind=kreal), dimension(:,:), allocatable :: WW
      real(kind=kreal), dimension(2) :: CG

      integer(kind=kint ) :: MAXIT, iterPREmax
      integer(kind=kint ) :: totalmpc

! local variables
      real   (kind=kreal):: TOL
      integer(kind=kint )::i
      real   (kind=kreal)::S_TIME,S1_TIME,E_TIME,E1_TIME, START_TIME, END_TIME
      real   (kind=kreal)::BNRM2,C2
      real   (kind=kreal)::RHO,RHO1,BETA,ALPHA,DNRM2
      real   (kind=kreal)::OMEGA

      integer(kind=kint), parameter :: R = 1
      integer(kind=kint), parameter :: RT= 2
      integer(kind=kint), parameter :: P = 3
      integer(kind=kint), parameter :: PT= 4
      integer(kind=kint), parameter :: S = 5
      integer(kind=kint), parameter :: ST= 1
      integer(kind=kint), parameter :: T = 6
      integer(kind=kint), parameter :: V = 7
      integer(kind=kint), parameter :: BT= 3
      integer(kind=kint), parameter ::TATX= 4
      integer(kind=kint), parameter :: WK= 8

      S_time= HECMW_WTIME()

!C===
!C +-------+
!C | INIT. |
!C +-------+
!C===
      my_rank = hecMESH%my_rank
      X => hecMAT%X
      B => hecMAT%B

      ITERlog = hecmw_mat_get_iterlog( hecMAT )
      TIMElog = hecmw_mat_get_timelog( hecMAT )
      MAXIT  = hecmw_mat_get_iter( hecMAT )
       TOL   = hecmw_mat_get_resid( hecMAT )

      totalmpc = hecMESH%mpc%n_mpc
      call hecmw_allreduce_I1 (hecMESH, totalmpc, hecmw_sum)

      ERROR = 0

      allocate (WW(3 * hecMAT%NP, 8))
      WW = 0.d0

      call hecmw_mpc_scale(hecMESH)

!C===
!C +----------------------------------------------+
!C | {r0}= [T']({b} - [A]{xg}) - [T'][A][T]{xini} |
!C +----------------------------------------------+
!C===

!C-- {bt}= [T']({b} - [A]{xg})
      if (totalmpc.eq.0) then
        do i = 1, hecMAT%N * 3
          WW(i,BT) = B(i)
        enddo
       else
        if (TIMElog.eq.1) then
        call hecmw_trans_b_33(hecMESH, hecMAT, B, WW(:,BT), WW(:,WK), Tcomm)
        else
        call hecmw_trans_b_33(hecMESH, hecMAT, B, WW(:,BT), WW(:,WK))
        endif
      endif

!C-- compute ||{bt}||
      if (TIMElog.eq.1) then
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,BT), WW(:,BT), BNRM2, Tcomm)
      else
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,BT), WW(:,BT), BNRM2)
      endif
      if (BNRM2.eq.0.d0) then
        iter = 0
        MAXIT = 0
        RESID = 0.d0
        X = 0.d0
      endif

!C-- {tatx} = [T'] [A] [T]{x}
      if (totalmpc.eq.0) then
        if (TIMElog.eq.1) then
        call hecmw_matvec_33(hecMESH, hecMAT, X, WW(:,TATX), Tcomm)
        else
        call hecmw_matvec_33(hecMESH, hecMAT, X, WW(:,TATX))
        endif
       else
        if (TIMElog.eq.1) then
        call hecmw_TtmatTvec_33(hecMESH, hecMAT, X, WW(:,TATX), WW(:,WK), Tcomm)
        else
        call hecmw_TtmatTvec_33(hecMESH, hecMAT, X, WW(:,TATX), WW(:,WK))
        endif
      endif

!C-- {r} = {bt} - {tatx}
      do i = 1, hecMAT%N * 3
        WW(i,R) = WW(i,BT) - WW(i,TATX)
        WW(i,RT) = WW(i,R)
      enddo

      E_time = HECMW_WTIME()
      Tset = Tset + E_time - S_time

      Tcomm = 0.d0
      S1_time = HECMW_WTIME()
!C
!C*************************************************************** iterative procedures start
!C
      do iter = 1, MAXIT

!C===
!C +-----------------+
!C | RHO= {r}{r_tld} |
!C +-----------------+
!C===
      if (TIMElog.eq.1) then
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,R), WW(:,RT), RHO, Tcomm)
      else
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,R), WW(:,RT), RHO)
      endif

!C===
!C +----------------------------------------+
!C | BETA= (RHO/RHO1) * (ALPHA/OMEGA)       |
!C | {p} = {r} + BETA * ( {p} - OMEGA*{v} ) |
!C +----------------------------------------+
!C===
      if ( iter.gt.1 ) then
        BETA = (RHO/RHO1) * (ALPHA/OMEGA)
        do i = 1, hecMAT%N * 3
          WW(i,P) = WW(i,R) + BETA * (WW(i,P) - OMEGA * WW(i,V))
        enddo
       else
        do i = 1, hecMAT%N * 3
          WW(i,P) = WW(i,R)
        enddo
      endif

!C===
!C +--------------------+
!C | {p_tld}= [Minv]{p} |
!C +--------------------+
!C===
      if (TIMElog.eq.1) then
      call hecmw_precond_33(hecMESH, hecMAT, WW(:, P), WW(:, PT), WW(:, WK), Tcomm)
      else
      call hecmw_precond_33(hecMESH, hecMAT, WW(:, P), WW(:, PT), WW(:, WK))
      endif

!C===
!C +-------------------------+
!C | {v}= [T'][A][T] {p_tld} |
!C +-------------------------+
!C===
      if (totalmpc.eq.0) then
        if (TIMElog.eq.1) then
        call hecmw_matvec_33(hecMESH, hecMAT, WW(:,PT), WW(:,V), Tcomm)
        else
        call hecmw_matvec_33(hecMESH, hecMAT, WW(:,PT), WW(:,V))
        endif
       else
        if (TIMElog.eq.1) then
        call hecmw_TtmatTvec_33(hecMESH, hecMAT, WW(:,PT), WW(:,V), WW(:,WK), Tcomm)
        else
        call hecmw_TtmatTvec_33(hecMESH, hecMAT, WW(:,PT), WW(:,V), WW(:,WK))
        endif
      endif

!C
!C-- calc. ALPHA
      if (TIMElog.eq.1) then
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,RT), WW(:,V), C2, Tcomm)
      else
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,RT), WW(:,V), C2)
      endif

      ALPHA = RHO / C2

!C
!C-- {s}= {r} - ALPHA*{V}
      do i = 1, hecMAT%N * 3
        WW(i,S) = WW(i,R) - ALPHA * WW(i,V)
      enddo

!C===
!C +--------------------+
!C | {s_tld}= [Minv]{s} |
!C +--------------------+
!C===
      if (TIMElog.eq.1) then
      call hecmw_precond_33(hecMESH, hecMAT, WW(:, S), WW(:, ST), WW(:, WK), Tcomm)
      else
      call hecmw_precond_33(hecMESH, hecMAT, WW(:, S), WW(:, ST), WW(:, WK))
      endif

!C===
!C +-------------------------+
!C | {t}= [T'][A][T] {s_tld} |
!C +-------------------------+
!C===
      if (totalmpc.eq.0) then
        if (TIMElog.eq.1) then
        call hecmw_matvec_33(hecMESH, hecMAT, WW(:,ST), WW(:,T), Tcomm)
        else
        call hecmw_matvec_33(hecMESH, hecMAT, WW(:,ST), WW(:,T))
        endif
       else
        if (TIMElog.eq.1) then
        call hecmw_TtmatTvec_33(hecMESH, hecMAT, WW(:,ST), WW(:,T), WW(:,WK), Tcomm)
        else
        call hecmw_TtmatTvec_33(hecMESH, hecMAT, WW(:,ST), WW(:,T), WW(:,WK))
        endif
      endif

!C===
!C +----------------------------+
!C | OMEGA= ({t}{s}) / ({t}{t}) |
!C +----------------------------+
!C===
      if (TIMElog.eq.1) then
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,T), WW(:,S), CG(1), Tcomm)
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,T), WW(:,T), CG(2), Tcomm)
      else
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,T), WW(:,S), CG(1))
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,T), WW(:,T), CG(2))
      endif

      OMEGA = CG(1) / CG(2)

!C===
!C +----------------+
!C | update {x},{r} |
!C +----------------+
!C===
      do i = 1, hecMAT%N * 3
        X (i) = X(i) + ALPHA * WW(i,PT) + OMEGA * WW(i,ST)
        WW(i,R) = WW(i,S) - OMEGA * WW(i,T)
      enddo

      if (TIMElog.eq.1) then
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,S), WW(:,S), DNRM2, Tcomm)
      else
      call hecmw_InnerProduct_R(hecMESH, 3, WW(:,S), WW(:,S), DNRM2)
      endif

      RESID= dsqrt(DNRM2/BNRM2)

!C##### ITERATION HISTORY
      if (my_rank.eq.0.and.ITERlog.eq.1) write (*,'(i7, 1pe16.6)') ITER, RESID
!C#####

      if ( RESID.le.TOL   ) exit
      if ( ITER .eq.MAXIT ) ERROR = -300

      RHO1 = RHO

      enddo
!C
!C*************************************************************** iterative procedures end
!C

      if (totalmpc.ne.0) then
        if (TIMElog.eq.1) then
        call hecmw_tback_x_33(hecMESH, X, WW(:,WK), Tcomm)
        else
        call hecmw_tback_x_33(hecMESH, X, WW(:,WK))
        endif
      endif

!C
!C-- INTERFACE data EXCHANGE
!C
      START_TIME = HECMW_WTIME()
      call hecmw_update_3_R (hecMESH, X, hecMAT%NP)
      END_TIME = HECMW_WTIME()
      Tcomm = Tcomm + END_TIME - START_TIME

      E1_time = HECMW_WTIME()
      Tsol = E1_time - S1_time

      deallocate (WW)

      end subroutine hecmw_solve_BiCGSTAB_33
      end module     hecmw_solver_BiCGSTAB_33
