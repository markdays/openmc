module geometry_header

  implicit none

!===============================================================================
! UNIVERSE defines a geometry that fills all phase space
!===============================================================================

  type Universe
     integer :: id                    ! Unique ID
     integer :: type                  ! Type
     integer :: n_cells               ! # of cells within
     integer, allocatable :: cells(:) ! List of cells within
     real(8) :: x0                    ! Translation in x-coordinate
     real(8) :: y0                    ! Translation in y-coordinate
     real(8) :: z0                    ! Translation in z-coordinate
  end type Universe

!===============================================================================
! LATTICE abstract type for ordered array of universes.
!===============================================================================

  type, abstract :: Lattice
    integer              :: id               ! Universe number for lattice
    real(8), allocatable :: pitch(:)         ! Pitch along each axis
    integer, allocatable :: universes(:,:,:) ! Specified universes
    integer              :: outside          ! Material to fill area outside
    integer              :: outer            ! universe to tile outside the lat
    logical              :: is_3d            ! Lattice has cells on z axis
    
    contains

    procedure(are_valid_indices_), deferred :: are_valid_indices
    procedure(get_indices_),       deferred :: get_indices
    procedure(get_local_xyz_),     deferred :: get_local_xyz
  end type Lattice

  abstract interface

!===============================================================================
! ARE_VALID_INDICES returns .true. if the given lattice indices fit within the
! bounds of the lattice.  Returns false otherwise.

    function are_valid_indices_(this, i_xyz) result(is_valid)
      import Lattice
      class(Lattice), intent(in) :: this
      integer,        intent(in) :: i_xyz(3)
      logical                    :: is_valid
    end function are_valid_indices_

!===============================================================================
! GET_INDICES returns the indices in a lattice for the given global xyz.

    function get_indices_(this, global_xyz) result(i_xyz)
      import Lattice
      class(Lattice), intent(in) :: this
      real(8),        intent(in) :: global_xyz(3)
      integer                    :: i_xyz(3)
    end function get_indices_

!===============================================================================
! GET_LOCAL_XYZ returns the translated local version of the given global xyz.

    function get_local_xyz_(this, global_xyz, i_xyz) result(local_xyz)
      import Lattice
      class(Lattice), intent(in) :: this
      real(8),        intent(in) :: global_xyz(3)
      integer,        intent(in) :: i_xyz(3)
      real(8)                    :: local_xyz(3)
    end function get_local_xyz_
  end interface

!===============================================================================
! RECTLATTICE extends LATTICE for rectilinear arrays.
!===============================================================================

  type, extends(Lattice) :: RectLattice
    integer              :: n_cells(3)     ! Number of cells along each axis
    real(8), allocatable :: lower_left(:)  ! Global lower-left corner of lat

    contains

    procedure :: are_valid_indices => valid_inds_rect
    procedure :: get_indices => get_inds_rect
    procedure :: get_local_xyz => get_local_rect
  end type RectLattice

!===============================================================================
! HEXLATTICE extends LATTICE for hexagonal (sometimes called triangular) arrays.
!===============================================================================

  type, extends(Lattice) :: HexLattice
    integer              :: n_rings   ! Number of radial ring cell positoins
    integer              :: n_axial   ! Number of axial cell positions
    real(8), allocatable :: center(:) ! Global center of lattice

    contains

    procedure :: are_valid_indices => valid_inds_hex
    procedure :: get_indices => get_inds_hex
    procedure :: get_local_xyz => get_local_hex
  end type HexLattice

!===============================================================================
! LATTICECONTAINER pointer array for storing lattices
!===============================================================================

  type LatticeContainer
    class(Lattice), allocatable :: obj
  end type LatticeContainer

!===============================================================================
! SURFACE type defines a first- or second-order surface that can be used to
! construct closed volumes (cells)
!===============================================================================

  type Surface
     integer :: id                     ! Unique ID
     integer :: type                   ! Type of surface
     real(8), allocatable :: coeffs(:) ! Definition of surface
     integer, allocatable :: & 
          neighbor_pos(:), &           ! List of cells on positive side
          neighbor_neg(:)              ! List of cells on negative side
     integer :: bc                     ! Boundary condition
  end type Surface

!===============================================================================
! CELL defines a closed volume by its bounding surfaces
!===============================================================================

  type Cell
     integer :: id         ! Unique ID
     integer :: type       ! Type of cell (normal, universe, lattice)
     integer :: universe   ! universe # this cell is in
     integer :: fill       ! universe # filling this cell
     integer :: material   ! Material within cell (0 for universe)
     integer :: n_surfaces ! Number of surfaces within
     integer, allocatable :: & 
          & surfaces(:)    ! List of surfaces bounding cell -- note that
                           ! parentheses, union, etc operators will be listed
                           ! here too

     ! Rotation matrix and translation vector
     real(8), allocatable :: rotation(:,:)
     real(8), allocatable :: translation(:)
  end type Cell

  ! array index of universe 0
  integer :: BASE_UNIVERSE

contains

!===============================================================================

  function valid_inds_rect(this, i_xyz) result(is_valid)
    class(RectLattice), intent(in) :: this
    integer,            intent(in) :: i_xyz(3)
    logical                        :: is_valid

    is_valid = all(i_xyz > 0 .and. i_xyz <= this % n_cells)
  end function valid_inds_rect

!===============================================================================

  function valid_inds_hex(this, i_xyz) result(is_valid)
    class(HexLattice), intent(in) :: this
    integer,           intent(in) :: i_xyz(3)
    logical                       :: is_valid

    is_valid = (all(i_xyz > 0) .and. &
               &i_xyz(1) < 2*this % n_rings .and. &
               &i_xyz(2) < 2*this % n_rings .and. &
               &i_xyz(1) + i_xyz(2) > this % n_rings .and. &
               &i_xyz(1) + i_xyz(2) < 3*this % n_rings .and. &
               &i_xyz(3) <= this % n_axial)
  end function valid_inds_hex

!===============================================================================

  function get_inds_rect(this, global_xyz) result(i_xyz)
    class(RectLattice), intent(in) :: this
    real(8),            intent(in) :: global_xyz(3)
    integer                        :: i_xyz(3)

    real(8) :: xyz(3)  ! global_xyz alias 

    xyz = global_xyz

    i_xyz(1) = ceiling((xyz(1) - this % lower_left(1))/this % pitch(1))
    i_xyz(2) = ceiling((xyz(2) - this % lower_left(2))/this % pitch(2))
    if (this % is_3d) then
      i_xyz(3) = ceiling((xyz(3) - this % lower_left(3))/this % pitch(3))
    else
      i_xyz(3) = 1
    end if
  end function get_inds_rect

!===============================================================================

  function get_inds_hex(this, global_xyz) result(i_xyz)
    class(HexLattice), intent(in) :: this
    real(8),           intent(in) :: global_xyz(3)
    integer                       :: i_xyz(3)

    real(8) :: xyz(3)    ! global_xyz alias 
    real(8) :: alpha     ! Skewed coord axis
    real(8) :: xyz_t(3)  ! Local xyz
    real(8) :: dists(4)  ! Squared distances from cell centers
    integer :: i, j, k   ! Iterators
    integer :: loc(1)    ! Minimum distance index

    xyz = global_xyz

    ! Index z direction.
    if (this % is_3d) then
      i_xyz(3) = ceiling((xyz(3) - this % center(3))/this % pitch(2) + 0.5_8)&
           &+ this % n_axial/2
    else
      i_xyz(3) = 1
    end if

    ! Convert coordinates into skewed bases.  The (x, alpha) basis is used to
    ! find the index of the global coordinates to within 4 cells.
    alpha = xyz(2) - xyz(1) / sqrt(3.0_8)
    i_xyz(1) = floor(xyz(1) / (sqrt(3.0_8) / 2.0_8 * this % pitch(1)))
    i_xyz(2) = floor(alpha / this % pitch(1))

    ! Add offset to indices (the center cell is (i_x, i_alpha) = (0, 0) but
    ! the array is offset so that the indices never go below 1).
    i_xyz(1) = i_xyz(1) + this % n_rings
    i_xyz(2) = i_xyz(2) + this % n_rings

    ! Calculate the (squared) distance between the particle and the centers of
    ! the four possible cells.  Regular hexagonal tiles form a centroidal
    ! Voronoi tessellation so the global xyz should be in the hexagonal cell
    ! that it is closest to the center of.  This method is used over a
    ! method that uses the remainders of the floor divisions above becasue it
    ! provides better finite precision performance.  Squared distances are
    ! used becasue they are more computationally efficient than normal
    ! distances.
    k = 1
    do i=0,1
      do j=0,1
        xyz_t = this % get_local_xyz(xyz, i_xyz + (/j, i, 0/))
        dists(k) = xyz_t(1)**2 + xyz_t(2)**2
        k = k + 1
      end do
    end do

    ! Select the minimum squared distance which corresponds to the cell the
    ! coordinates are in.
    loc = minloc(dists)
    if (loc(1) == 2) then
      i_xyz = i_xyz + (/1, 0, 0/)
    else if (loc(1) == 3) then
      i_xyz = i_xyz + (/0, 1, 0/)
    else if (loc(1) == 4) then
      i_xyz = i_xyz + (/1, 1, 0/)
    end if
  end function get_inds_hex

!===============================================================================

  function get_local_rect(this, global_xyz, i_xyz) result(local_xyz)
    class(RectLattice), intent(in) :: this
    real(8),            intent(in) :: global_xyz(3)
    integer,            intent(in) :: i_xyz(3)
    real(8)                        :: local_xyz(3)

    real(8) :: xyz(3)  ! global_xyz alias

    xyz = global_xyz

    local_xyz(1) = xyz(1) - (this % lower_left(1) + &
         &(i_xyz(1) - 0.5_8)*this % pitch(1))
    local_xyz(2) = xyz(2) - (this % lower_left(2) + &
         &(i_xyz(2) - 0.5_8)*this % pitch(2))
    if (this % is_3d) then
      local_xyz(3) = xyz(3) - (this % lower_left(3) + &
           &(i_xyz(3) - 0.5_8)*this % pitch(3))
    else
      local_xyz(3) = xyz(3)
    end if
  end function get_local_rect

!===============================================================================

  function get_local_hex(this, global_xyz, i_xyz) result(local_xyz)
    class(HexLattice), intent(in) :: this
    real(8),           intent(in) :: global_xyz(3)
    integer,           intent(in) :: i_xyz(3)
    real(8)                       :: local_xyz(3)

    real(8) :: xyz(3)  ! global_xyz alias

    xyz = global_xyz

    ! x_l = x_g - (center + pitch_x*cos(30)*index_x)
    local_xyz(1) = xyz(1) - (this % center(1) + &
         &sqrt(3.0_8) / 2.0_8 * (i_xyz(1) - this % n_rings) * this % pitch(1))
    ! y_l = y_g - (center + pitch_x*index_x + pitch_y*sin(30)*index_y)
    local_xyz(2) = xyz(2) - (this % center(2) + &
         &(i_xyz(2) - this % n_rings) * this % pitch(1) + &
         &(i_xyz(1) - this % n_rings) * this % pitch(1) / 2.0_8)
    if (this % is_3d) then
      local_xyz(3) = xyz(3) - this % center(3) &
           &+ (this % n_axial/2 - i_xyz(3) + 1) * this % pitch(2)
    else
      local_xyz(3) = xyz(3)
    end if
  end function get_local_hex

end module geometry_header
