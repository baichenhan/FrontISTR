!-------------------------------------------------------------------------------
! Copyright (c) 2019 FrontISTR Commons
! This software is released under the MIT License, see LICENSE.txt
!-------------------------------------------------------------------------------

module hecmw_matrix_contact_lagrange
  use hecmw_util
  implicit none

  private
  public :: nodeRelated
  public :: hecmw_construct_nodeRelated_from_hecMAT
  public :: hecmw_init_nodeRelated_from_org
  public :: hecmw_ass_nodeRelated_from_contact_pair

  !> Structure for defining stiffness matrix structure
  type nodeRelated
    integer(kind=kint)          :: num_node = 0, num_lagrange = 0 !< total number of related nodes and Lagrange multipliers
    integer(kind=kint), pointer :: id_node(:) => null() !< list of related nodes
    integer(kind=kint), pointer :: id_lagrange(:) => null() !< list of related Lagrange multipliers
  end type

contains

  !> \brief This subroutine saves original matrix structure constructed originally by hecMW_matrix
  subroutine hecmw_construct_nodeRelated_from_hecMAT(hecMAT, NPL, NPU, list_nodeRelated)
    type(hecmwST_matrix), intent(in)          :: hecMAT !< type hecmwST_matrix
    integer(kind=kint), intent(out)           :: NPL !< original number of non-zero items(lower)
    integer(kind=kint), intent(out)           :: NPU !< original number of non-zero items(upper)
    type(nodeRelated), pointer, intent(inout) :: list_nodeRelated(:) !< nodeRelated structure of matrix

    integer(kind=kint)   :: numL, numU, num_nodeRelated !< original number of nodes related to each node
    integer(kind=kint)   :: i, j
    integer(kind=kint)   :: ierr

    NPL = hecMAT%NPL; NPU = hecMAT%NPU

    if( associated(list_nodeRelated) ) return
    allocate(list_nodeRelated(hecMAT%NP), stat=ierr)
    if( ierr /= 0) stop " Allocation error, list_nodeRelated "

    do i = 1, hecMAT%NP

      numL = hecMAT%indexL(i) - hecMAT%indexL(i-1)
      numU = hecMAT%indexU(i) - hecMAT%indexU(i-1)

      num_nodeRelated = numL + numU + 1

      allocate(list_nodeRelated(i)%id_node(num_nodeRelated), stat=ierr)
      if( ierr /= 0) stop " Allocation error, list_nodeRelated%id_node "

      list_nodeRelated(i)%num_node = num_nodeRelated

      do j = 1, numL
        list_nodeRelated(i)%id_node(j) = hecMAT%itemL(hecMAT%indexL(i-1)+j)
      enddo
      list_nodeRelated(i)%id_node(numL+1) = i
      do j = 1, numU
        list_nodeRelated(i)%id_node(numL+1+j) = hecMAT%itemU(hecMAT%indexU(i-1)+j)
      enddo

    enddo

  end subroutine hecmw_construct_nodeRelated_from_hecMAT

  !> Get original list of related nodes
  subroutine hecmw_init_nodeRelated_from_org(np,num_lagrange,is_contact_active,list_nodeRelated_org,list_nodeRelated)
    integer(kind=kint), intent(in)  :: np, num_lagrange !< total number of nodes
    logical, intent(in)             :: is_contact_active
    type(nodeRelated), pointer, intent(in)    :: list_nodeRelated_org(:) !< original structure of matrix
    type(nodeRelated), pointer, intent(inout) :: list_nodeRelated(:) !< current structure of matrix

    integer(kind=kint)            :: num_nodeRelated_org !< original number of nodes related to each node
    integer(kind=kint)            :: i, ierr

    allocate(list_nodeRelated(np+num_lagrange), stat=ierr)
    if( ierr /= 0) stop " Allocation error, list_nodeRelated "

    do i = 1, np  !hecMAT%NP
      num_nodeRelated_org = list_nodeRelated_org(i)%num_node
      allocate(list_nodeRelated(i)%id_node(num_nodeRelated_org), stat=ierr)
      if( ierr /= 0) stop " Allocation error, list_nodeRelated%id_node "
      list_nodeRelated(i)%num_node = num_nodeRelated_org
      list_nodeRelated(i)%id_node(1:num_nodeRelated_org) = list_nodeRelated_org(i)%id_node(1:num_nodeRelated_org)
    enddo

    if( is_contact_active ) then
      do i = np+1, np+num_lagrange  !hecMAT%NP+1, hecMAT%NP+num_lagrange
        allocate(list_nodeRelated(i)%id_lagrange(5), stat=ierr)
        if( ierr /= 0) stop " Allocation error, list_nodeRelated%id_lagrange "
        list_nodeRelated(i)%num_lagrange = 0
        list_nodeRelated(i)%id_lagrange = 0
      enddo
    endif

  end subroutine hecmw_init_nodeRelated_from_org

  subroutine hecmw_ass_nodeRelated_from_contact_pair(np, nnode, ndLocal, count_lagrange, permission, &
          & necessary_to_insert_node, list_nodeRelated_org, list_nodeRelated, countNon0LU_node, countNon0LU_lagrange )
    integer(kind=kint), intent(in)            :: np
    integer(kind=kint), intent(in)            :: nnode
    integer(kind=kint), intent(in)            :: ndLocal(:)
    integer(kind=kint), intent(in)            :: count_lagrange !< counter of Lagrange multiplier
    logical, intent(inout)                    :: permission
    logical, intent(in)                       :: necessary_to_insert_node
    type(nodeRelated), pointer, intent(in)    :: list_nodeRelated_org(:) !< original structure of matrix
    type(nodeRelated), pointer, intent(inout) :: list_nodeRelated(:) !< current structure of matrix
    integer(kind=kint), intent(inout)         :: countNon0LU_node, countNon0LU_lagrange !< counters of node-based
    !< number of non-zero items

    integer(kind=kint)            :: k, l, num, num_nodeRelated_org, ierr

    do k = 1, nnode+1

      if( .not. associated(list_nodeRelated(ndLocal(k))%id_lagrange) )then
        num = 10
        !             if( k == 1 ) num = 1
        allocate(list_nodeRelated(ndLocal(k))%id_lagrange(num),stat=ierr)
        if( ierr /= 0) stop " Allocation error, list_nodeRelated%id_lagrange "
        list_nodeRelated(ndLocal(k))%num_lagrange = 0
        list_nodeRelated(ndLocal(k))%id_lagrange = 0
      endif

      if( necessary_to_insert_node ) then
        num_nodeRelated_org = list_nodeRelated_org(ndLocal(k))%num_node
        if( list_nodeRelated(ndLocal(k))%num_node == num_nodeRelated_org )then
          num = 10
          if(k==1) num = 4
          call reallocate_memory(num,list_nodeRelated(ndLocal(k)))
        endif
      endif

      call insert_lagrange(k,count_lagrange,list_nodeRelated(ndLocal(k)),countNon0LU_lagrange,permission)

      do l = k, nnode+1
        if( necessary_to_insert_node ) then
          if( k /= l) then
            num_nodeRelated_org = list_nodeRelated_org(ndLocal(k))%num_node
            call insert_node(ndLocal(l),list_nodeRelated(ndLocal(k)),countNon0LU_node)
            num_nodeRelated_org = list_nodeRelated_org(ndLocal(l))%num_node
            if( list_nodeRelated(ndLocal(l))%num_node == num_nodeRelated_org )then
              num = 10
              call reallocate_memory(num,list_nodeRelated(ndLocal(l)))
            endif
            call insert_node(ndLocal(k),list_nodeRelated(ndLocal(l)),countNon0LU_node)
          endif
        endif

        if(k == 1) &
          call insert_lagrange(0,ndLocal(l),list_nodeRelated(np+count_lagrange),countNon0LU_lagrange,permission)

      enddo

    enddo
  end subroutine hecmw_ass_nodeRelated_from_contact_pair

  !> Insert a Lagrange multiplier in list of related Lagrange multipliers
  subroutine insert_lagrange(i,id_lagrange,list_node,countNon0_lagrange,permission)

    type(nodeRelated), intent(inout)  :: list_node !< type nodeRelated
    integer(kind=kint), intent(in)    :: i, id_lagrange !< local number of node in current contact pair
    !< Lagrange multiplier ID
    integer(kind=kint), intent(inout) :: countNon0_lagrange !< counter of node-based number of non-zero items
    !< in Lagrange multiplier-related matrix
    logical, intent(inout)            :: permission

    integer(kind=kint) :: ierr, num_lagrange, location
    integer(kind=kint), allocatable :: id_lagrange_save(:)

    character(len=1)   :: answer

    ierr = 0

    num_lagrange = count(list_node%id_lagrange /= 0 )

    !      if( i == 1 .and. num_lagrange /= 0) return
    if( i == 1 .and. num_lagrange /= 0 .and. .not. permission) then
      1  write(*,*) '##Error: node is both slave and master node simultaneously !'
      write(*,*) '         Please check contact surface definition !'
      write(*,'(''          Do you want to continue(y/n)):'',$)')
      read(*,'(A1)',err=1) answer
      if(answer == 'Y' .OR. answer == 'y')then
        permission = .true.
      else
        stop
      endif
    endif

    if (num_lagrange == 0)then
      list_node%num_lagrange = 1
      list_node%id_lagrange(1) = id_lagrange
      countNon0_lagrange = countNon0_lagrange + 1
    else
      allocate(id_lagrange_save(num_lagrange))
      id_lagrange_save(1:num_lagrange) = list_node%id_lagrange(1:num_lagrange)
      location = find_locationINarray(id_lagrange,num_lagrange,list_node%id_lagrange)
      if(location /= 0)then
        num_lagrange = num_lagrange + 1
        if( num_lagrange > size(list_node%id_lagrange)) then
          deallocate(list_node%id_lagrange)
          allocate(list_node%id_lagrange(num_lagrange),stat=ierr)
          if( ierr /= 0 ) stop " Allocation error, list_nodeRelated%id_lagrange "
        endif
        list_node%num_lagrange = num_lagrange
        list_node%id_lagrange(location) = id_lagrange
        if(location /= 1) list_node%id_lagrange(1:location-1) = id_lagrange_save(1:location-1)
        if(location /= num_lagrange) list_node%id_lagrange(location+1:num_lagrange) = id_lagrange_save(location:num_lagrange-1)
        countNon0_lagrange = countNon0_lagrange + 1
      endif
      deallocate(id_lagrange_save)
    endif

  end subroutine insert_lagrange

  !> Insert a node in list of related nodes
  subroutine insert_node(id_node,list_node,countNon0_node)

    type(nodeRelated)  :: list_node !< type nodeRelated
    integer(kind=kint) :: id_node !< local number of node in current contact pair
    !< global number of node
    integer(kind=kint) :: countNon0_node !< counter of node-based number of non-zero items in displacement-related matrix
    integer(kind=kint) :: ierr, num_node, location
    integer(kind=kint),allocatable :: id_node_save(:)

    ierr = 0

    num_node = list_node%num_node
    allocate(id_node_save(num_node))
    id_node_save(1:num_node) = list_node%id_node(1:num_node)
    location = find_locationINarray(id_node,num_node,list_node%id_node)
    if(location /= 0)then
      num_node = num_node + 1
      if( num_node > size(list_node%id_node)) then
        deallocate(list_node%id_node)
        allocate(list_node%id_node(num_node),stat=ierr)
        if( ierr /= 0) stop " Allocation error, list_nodeRelated%id_node "
      endif
      list_node%num_node = num_node
      list_node%id_node(location) = id_node
      if(location /= 1) list_node%id_node(1:location-1) = id_node_save(1:location-1)
      if(location /= num_node) list_node%id_node(location+1:num_node) = id_node_save(location:num_node-1)
      countNon0_node = countNon0_node + 1
    endif
    deallocate(id_node_save)

  end subroutine insert_node

  !> Find location of an item in an array by bisection method
  integer function find_locationINarray(item,n,a)
    integer(kind=kint), intent(in)             :: item, n !< item to be found; length of array
    integer(kind=kint), pointer, intent(inout) :: a(:) !< array

    integer(kind=kint)           :: l, r, m

    find_locationINarray = 0

    l = 1 ; r = n ; m = (l+r)/2
    if( item == a(l) .or. item == a(r) )then
      return
    elseif( item < a(l) )then
      find_locationINarray = 1
      return
    elseif( item > a(r) )then
      find_locationINarray = n + 1
      return
    endif

    do while ( l <= r)
      if( item > a(m) ) then
        l = m + 1
        m = (l + r)/2
      elseif( item < a(m) ) then
        r = m - 1
        m = (l + r)/2
      elseif( item == a(m) )then
        return
      endif
    enddo

    find_locationINarray = m + 1

  end function find_locationINarray

  !> Reallocate memory for list_relatedNodes
  subroutine reallocate_memory(num,list_node)
    integer(kind=kint), intent(in)   :: num !< length to be added
    type(nodeRelated),intent(inout)  :: list_node !< type nodeRelated

    integer(kind=kint) :: num_node_org !< original number of related nodes
    !< before reallocation
    integer(kind=kint) :: id_save(1000)
    integer(kind=kint) :: ierr

    num_node_org = size(list_node%id_node)
    id_save(1:num_node_org) = list_node%id_node(1:num_node_org)
    deallocate(list_node%id_node)
    allocate(list_node%id_node(num_node_org+num),stat=ierr)
    if( ierr /= 0) stop " reAllocation error, list_nodeRelated%id_node "
    list_node%id_node = 0
    list_node%id_node(1:num_node_org) = id_save(1:num_node_org)

  end subroutine reallocate_memory

end module hecmw_matrix_contact_lagrange
