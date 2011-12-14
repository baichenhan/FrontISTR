!======================================================================!
!                                                                      !
! Software Name : FrontISTR Ver. 3.2                                   !
!                                                                      !
!      Module Name : Static Analysis                                   !
!                                                                      !
!            Written by K. Sato(Advancesoft), X. YUAN(AdavanceSoft)    !
!                                                                      !
!                                                                      !
!      Contact address :  IIS,The University of Tokyo, CISS            !
!                                                                      !
!      "Structural Analysis for Large Scale Assembly"                  !
!                                                                      !
!======================================================================!
!======================================================================!
!
!> \brief  This module provides function to calcualte residual of nodal force.
!!
!>  \author     K. Sato(Advancesoft), X. YUAN(AdavanceSoft)
!>  \date       2009/09/14
!>  \version    0.00
!!
!======================================================================!
module m_fstr_Residual
  use hecmw
  implicit none
  
  contains

!C---------------------------------------------------------------------*
      subroutine fstr_Update_NDForce(cstep,hecMESH,hecMAT,fstrSOLID )
!C---------------------------------------------------------------------*
!> In this subroutine, nodal force arose from prescribed displacement constarints 
!> are cleared and nodal force residual is calculated. 
!> Those constraints considered here includes:
!!-#  nodal displacement
!!-#  equation (or mpc) 
      use m_fstr
      use mULoad
      integer(kind=kint), intent(in)       :: cstep      !< current step
      type (hecmwST_local_mesh),intent(in) :: hecMESH    !< mesh information
      type (hecmwST_matrix),intent(inout)  :: hecMAT     !< linear equation, its right side modified here
      type (fstr_solid), intent(inout)     :: fstrSOLID  !< we need boundary conditions of curr step
!    Local variables
      integer(kind=kint) ndof,ig0,ig,ityp,iS0,iE0,ik,in,idof1,idof2,idof
      integer(kind=kint) :: grpid  
      real(kind=kreal) :: rhs, lambda, factor

      factor = fstrSOLID%factor(2)
      if( cstep<=fstrSOLID%nstep_tot .and. fstrSOLID%step_ctrl(cstep)%solution==stepVisco ) factor=1.d0
!    Set residual load
      do idof=1, hecMESH%n_node*  hecMESH%n_dof 
        hecMAT%B(idof)=factor*fstrSOLID%GL(idof)-fstrSOLID%QFORCE(idof)
      end do
	  ndof = hecMAT%NDOF
	  
!    Consider Uload
      call uResidual( cstep, factor, hecMAT%B )

!    Consider EQUATION condition
      do ig0=1,hecMESH%mpc%n_mpc
        iS0= hecMESH%mpc%mpc_index(ig0-1)+1
        iE0= hecMESH%mpc%mpc_index(ig0)
        ! Suppose the lagrange multiplier= first dof of first node
        in = hecMESH%mpc%mpc_item(iS0)
        idof = hecMESH%mpc%mpc_dof(iS0)
        rhs = hecMESH%mpc%mpc_val(iS0)
        lambda = hecMAT%B(ndof*(in-1)+idof)/rhs
        ! update nodal residual
        do ik= iS0, iE0
          in = hecMESH%mpc%mpc_item(ik)
          idof = hecMESH%mpc%mpc_dof(ik)
          rhs = hecMESH%mpc%mpc_val(ik)
          hecMAT%B(ndof*(in-1)+idof) = hecMAT%B(ndof*(in-1)+idof) &
              - rhs*lambda 
        enddo
      enddo
     
!    Consider SPC condition
      do ig0= 1, fstrSOLID%BOUNDARY_ngrp_tot
        grpid = fstrSOLID%BOUNDARY_ngrp_GRPID(ig0)
        if( .not. fstr_isBoundaryActive( fstrSOLID, grpid, cstep ) ) cycle
        ig= fstrSOLID%BOUNDARY_ngrp_ID(ig0)
        rhs= fstrSOLID%BOUNDARY_ngrp_val(ig0)
        ityp= fstrSOLID%BOUNDARY_ngrp_type(ig0)
        iS0= hecMESH%node_group%grp_index(ig-1) + 1
        iE0= hecMESH%node_group%grp_index(ig  )
        do ik= iS0, iE0
          in   = hecMESH%node_group%grp_item(ik)
          idof1 = ityp/10
          idof2 = ityp - idof1*10
          do idof=idof1,idof2
            hecMAT%B( ndof*(in-1) + idof ) = 0.d0
          enddo
        enddo
      enddo
 
!    	  
      if( ndof==3 ) then
        call hecmw_update_3_R(hecMESH,hecMAT%B,hecMESH%n_node)
      else if( ndof==2 ) then
        call hecmw_update_2_R(hecMESH,hecMAT%B,hecMESH%n_node)
      else if( ndof==6 ) then
        call hecmw_update_m_R(hecMESH,hecMAT%B,hecMESH%n_node,6)
      endif

      end subroutine fstr_Update_NDForce
	  
!> Calculate magnitude of a real vector
      real(kind=kreal) function fstr_get_residual( force, hecMESH )
      use m_fstr
      real(kind=kreal), intent(in)         :: force(:)
      type (hecmwST_local_mesh),intent(in) :: hecMESH    !< mesh information
      integer :: i
      fstr_get_residual =0.d0
      do i=1,hecMESH%n_node*  hecMESH%n_dof
        fstr_get_residual = fstr_get_residual + force(i)*force(i)
      enddo
    !  fstr_get_residual=dot_product( force(:), force(:) )
    !  fstr_get_residual = fstr_get_residual/hecMESH%n_node
      if( hecMESH%my_rank==0) then
         write(IMSG,*) '####fstrNLGEOM_SetResidual finished'
      end if
      end function
      
!> Calculate square norm      
      real(kind=kreal) function fstr_get_norm_contact(flag,hecMESH,hecMAT,fstrSOLID,fstrMAT)
      use m_fstr
      use fstr_matrix_con_contact
      type (hecmwST_local_mesh),            intent(in) :: hecMESH    !< mesh information
      type (hecmwST_matrix),                intent(in) :: hecMAT
      type (fstr_solid),                    intent(in) :: fstrSOLID 
      type (fstrST_matrix_contact_lagrange),intent(in) :: fstrMAT 
      character(len=13)                                :: flag   
      integer :: i
       fstr_get_norm_contact = 0.0d0   
       if( flag=='residualForce' )then
         do i=1,hecMESH%n_node*hecMESH%n_dof + fstrMAT%num_lagrange
           fstr_get_norm_contact = fstr_get_norm_contact + hecMAT%B(i)*hecMAT%B(i)
         enddo
       elseif( flag=='        force' )then
         do i=1,hecMESH%n_node*hecMESH%n_dof 
           fstr_get_norm_contact = fstr_get_norm_contact + fstrSOLID%QFORCE(i)*fstrSOLID%QFORCE(i)
         enddo
       endif
      end function        

end module m_fstr_Residual