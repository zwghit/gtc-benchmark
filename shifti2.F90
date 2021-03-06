! Copyright 2008 Z. Lin <zhihongl@uci.edu>
!
! This file is part of GTC version 1.
!
! GTC version 1 is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! GTC version 1 is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with GTC version 1.  If not, see <http://www.gnu.org/licenses/>.

subroutine shifti
  use global_parameters
  use particle_array
  use particle_decomp
  implicit none
  
  integer i,m,msendleft(2),msendright(2),mrecvleft(2),mrecvright(2),mtop,&
       kzi(mimax),m0,msend,mrecv,idest,isource,isendtag,irecvtag,nzion,&
       iright(mimax),ileft(mimax),isendcount,irecvcount,&
       istatus(MPI_STATUS_SIZE),ierror,iteration,lasth
  integer mi_total
  real(wp),dimension(:,:),allocatable :: recvbuf,sendleft,sendright
  real(wp) zetaright,zetaleft,pi_inv
  character(len=8) cdum
#ifdef _OPENMP
  integer msleft(32,0:15),msright(32,0:15)
  integer nthreads,gnthreads,iam,delm,mbeg,mend,omp_get_num_threads,&
       omp_get_thread_num
#endif

!  if(istep==1 .and. irk==2)then
!    write(mype+10,*)mi
!    do i=1,mi
!       write(mype+10,*)zion(:,i)
!    enddo
!    close(mype+10)
!  endif


  nzion=2*nparam   ! nzion=14 if track_particles=1, =12 otherwise
  pi_inv=1.0/pi
  m0=1
  iteration=0
  
100 iteration=iteration+1
  if(iteration>numberpe)then
     write(0,*)'endless particle sorting loop at PE=',mype
     call MPI_ABORT(MPI_COMM_WORLD,1,ierror)
  endif

  msend=0
  msendright=0
  msendleft=0

  if(m0 <= mi)then
!$omp parallel do private(m)
     do m=m0,mi
        kzi(m)=0
     enddo

#ifdef _OPENMP
! This section of code (down to #else) is included by the preprocessor when
! the compilation is performed with OpenMP support. We must then use a few
! temporary arrays and add some work distribution code.
  msleft=0
  msright=0

! First we start the parallel region with !$omp parallel

!$omp parallel private(nthreads,iam,delm,i,mbeg,mend,m,zetaright,zetaleft) &
!$omp& shared(gnthreads)
  nthreads=omp_get_num_threads()    !Get the number of threads ready to work
  iam=omp_get_thread_num()          !Get my thread number (position)
  delm=(mi-m0+1)/nthreads       !Calculate the number of steps per thread
  i=mod((mi-m0+1),nthreads)
!$omp single              !Put nthread in global variable for later use.
  gnthreads=nthreads      !nthread is the same for all threads so only one
!$omp end single nowait   !of them needs to copy the value in gnthreads

! We now distribute the work between the threads. The loop over the particles
! is distributed equally (as much as possible) between them.
  mbeg=m0+min(iam,i)*(delm+1)+max(0,(iam-i))*delm
  mend=mbeg+delm+(min((iam+1),i)/(iam+1))-1

! label particle to be moved 
     do m=mbeg,mend
        zetaright=min(2.0*pi,zion(3,m))-zetamax
        zetaleft=zion(3,m)-zetamin
        
        if( zetaright*zetaleft > 0 )then
           zetaright=zetaright*0.5*pi_inv
           zetaright=zetaright-real(floor(zetaright))
           msright(3,iam)=msright(3,iam)+1
           kzi(mbeg+msright(3,iam)-1)=m
           
           if( zetaright < 0.5 )then
! particle to move right               
              msright(1,iam)=msright(1,iam)+1
              iright(mbeg+msright(1,iam)-1)=m
! keep track of tracer
              if( nhybrid == 0 .and. m == ntracer )then
                 msright(2,iam)=msright(1,iam)
                 ntracer=0
              endif

! particle to move left
           else
              msleft(1,iam)=msleft(1,iam)+1
              ileft(mbeg+msleft(1,iam)-1)=m
              if( nhybrid == 0 .and. m == ntracer )then
                 msleft(2,iam)=msleft(1,iam)
                 ntracer=0
              endif
           endif
        endif
     enddo
! End of the OpenMP parallel region
!$omp end parallel

! Now that we are out of the parallel region we need to gather and rearrange
! the results of the multi-threaded calculation. We need to end up with the
! same arrays as for the sequential (single-threaded) calculation.
     do m=0,gnthreads-1
        delm=(mi-m0+1)/gnthreads
        i=mod((mi-m0+1),gnthreads)
        mbeg=m0+min(m,i)*(delm+1)+max(0,(m-i))*delm
        if( msleft(2,m) /= 0 )msendleft(2)=msendleft(1)+msleft(2,m)
        do i=1,msleft(1,m)
           ileft(msendleft(1)+i)=ileft(mbeg+i-1)
        enddo
        msendleft(1)=msendleft(1)+msleft(1,m)
        if( msright(2,m) /= 0 )msendright(2)=msendright(1)+msright(2,m)
        do i=1,msright(1,m)
           iright(msendright(1)+i)=iright(mbeg+i-1)
        enddo
        msendright(1)=msendright(1)+msright(1,m)
        do i=1,msright(3,m)
           kzi(msend+i)=kzi(mbeg+i-1)
        enddo
        msend=msend+msright(3,m)
     enddo

#else
!  This section of code replaces the section above when the compilation does
!  NOT include the OpenMP support option. Temporary arrays msleft and msright
!  are not needed as well as the extra code for thread work distribution.

     do m=m0,mi
        zetaright=min(2.0*pi,zion(3,m))-zetamax
        zetaleft=zion(3,m)-zetamin

        if( zetaright*zetaleft > 0 )then
           zetaright=zetaright*0.5*pi_inv
           zetaright=zetaright-real(floor(zetaright))
           msend=msend+1
           kzi(msend)=m

           if( zetaright < 0.5 )then
! # of particle to move right
              msendright(1)=msendright(1)+1
              iright(msendright(1))=m
! keep track of tracer
              if( nhybrid == 0 .and. m == ntracer )then
                 msendright(2)=msendright(1)
                 ntracer=0
              endif

! # of particle to move left
           else
              msendleft(1)=msendleft(1)+1
              ileft(msendleft(1))=m
              if( nhybrid == 0 .and. m == ntracer )then
                 msendleft(2)=msendleft(1)
                 ntracer=0
              endif
           endif
        endif
     enddo

#endif

  endif

  if(iteration>1)then
! total # of particles to be shifted
     mrecv=0
     msend=msendleft(1)+msendright(1)

     call MPI_ALLREDUCE(msend,mrecv,1,MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,ierror)

! no particle to be shifted, return
     if ( mrecv == 0 ) then
           !  if(istep==1 .and. irk==2)then
           !     write(mype+20,*)mi
           !     do i=1,mi
           !        write(mype+20,*)zion(:,i)
           !     enddo
           !     close(mype+20)
           !  endif
           !  call MPI_REDUCE(mi,mi_total,1,MPI_INTEGER,MPI_SUM,0,MPI_COMM_WORLD,ierror)
           !  if(mype==0)write(0,*)' *** in shifti: mi total =',mi_total
        return
     endif
  endif

! an extra space to prevent zero size when msendright(1)=msendleft(1)=0
  allocate(sendright(nzion,max(msendright(1),1)),sendleft(nzion,max(msendleft(1),1)))

! pack particle to move right
!$omp parallel do private(m)
     do m=1,msendright(1)
        sendright(1:nparam,m)=zion(1:nparam,iright(m))
        sendright(nparam+1:nzion,m)=zion0(1:nparam,iright(m))
     enddo

! pack particle to move left
!$omp parallel do private(m)
     do m=1,msendleft(1)    
        sendleft(1:nparam,m)=zion(1:nparam,ileft(m))
        sendleft(nparam+1:nzion,m)=zion0(1:nparam,ileft(m))
     enddo

! send # of particle to move right to neighboring PEs of same particle
! domain.
  mrecvleft=0
  idest=right_pe
  isource=left_pe
  isendtag=myrank_toroidal
  irecvtag=isource
  call MPI_SENDRECV(msendright,2,MPI_INTEGER,idest,isendtag,&
       mrecvleft,2,MPI_INTEGER,isource,irecvtag,toroidal_comm,istatus,ierror)
  
! send # of particle to move left
  mrecvright=0
  idest=left_pe
  isource=right_pe
  isendtag=myrank_toroidal
  irecvtag=isource
  call MPI_SENDRECV(msendleft,2,MPI_INTEGER,idest,isendtag,&
       mrecvright,2,MPI_INTEGER,isource,irecvtag,toroidal_comm,istatus,ierror)
 
! Total number of particles to receive
  mrecv=mrecvleft(1)+mrecvright(1)

! need extra particle array
  if(mi-msend+mrecv > mimax)then
     write(0,*)"need bigger particle array",mimax,mi+mrecvleft(1)+mrecvright(1)
     call MPI_ABORT(MPI_COMM_WORLD,1,ierror)
! We assume that there is not enough memory available to this process to
! allow the allocation of a temporary array to hold the particle data.
! We use a disk file instead although this slows down the code.
! open disk file
!     write(cdum,'("TEMP.",i5.5)')mype
!     open(111,file=cdum,status='replace',form='unformatted')
!    
! record particle information to file
!     write(111)zion(1:nparam,1:mi)
!     write(111)zion0(1:nparam,1:mi)
     
! make bigger array
!     deallocate(zion,zion0)
!     mimax=2*(mi-msend+mrecv)-mimax
!     allocate(zion(nparam,mimax),zion0(nparam,mimax))
     
! read back particle information
!     rewind(111)
!     read(111)zion(1:nparam,1:mi)
!     read(111)zion0(1:nparam,1:mi)
!     close(111)
  endif

! Allocate receive buffer
  allocate(recvbuf(nzion,max(mrecv+1,1)))

! send particles to right and receive from left
  recvbuf=0.0_wp
  idest=right_pe
  isource=left_pe
  isendtag=myrank_toroidal
  irecvtag=isource
  isendcount=msendright(1)*nzion
  irecvcount=mrecvleft(1)*nzion
  call MPI_SENDRECV(sendright,isendcount,mpi_Rsize,idest,isendtag,recvbuf,&
       irecvcount,mpi_Rsize,isource,irecvtag,toroidal_comm,istatus,ierror)

! send particles to left and receive from right
  idest=left_pe
  isource=right_pe
  isendtag=myrank_toroidal
  irecvtag=isource
  isendcount=msendleft(1)*nzion
  irecvcount=mrecvright(1)*nzion
  call MPI_SENDRECV(sendleft,isendcount,mpi_Rsize,idest,isendtag,&
       recvbuf(1,mrecvleft(1)+1),irecvcount,mpi_Rsize,isource,irecvtag,&
       toroidal_comm,istatus,ierror)
  
! tracer particle
  if( nhybrid == 0 .and. mrecvleft(2) > 0 )then
     ntracer=mi+mrecvleft(2)
  elseif( nhybrid == 0 .and. mrecvright(2) > 0 )then
     ntracer=mi+mrecvleft(1)+mrecvright(2)
  endif

! The particle array zion() now has "msend" holes at different positions
! in the array. We want to fill these holes with the received particles.
! We need to check for the possibility of having more holes than received
! particles or vice versa. The positions of the holes have been saved in
! the kzi() vector.
  do m=1,min(msend,mrecv)
     zion(1:nparam,kzi(m))=recvbuf(1:nparam,m)
     zion0(1:nparam,kzi(m))=recvbuf(nparam+1:nzion,m)
  enddo

! We now check if the tracer particle is on this processor, which is indicated
! by a non-zero value of mrecvleft(2) or mrecvright(2). The non-zero value
! indicates the position of that tracer particle in the recvbuf array. If that
! value is less than or equal to the smallest number between msend and mrecv, we
! know that the tracer is now particle zion(:,kzi(mrecv{left,right}(2)).
  if( nhybrid==0 )then
     if( mrecvleft(2) > 0 .and. mrecvleft(2) <= min(msend,mrecv))then
        ntracer=kzi(mrecvleft(2))
     elseif( mrecvright(2) > 0 .and. mrecvright(2) <= min(msend,mrecv))then
        ntracer=kzi(mrecvright(2))
     endif
  endif

! If mrecv > msend, we have some leftover received particles after having
! filled all the holes. We place these extra particles in the empty space
! at the top of the particle array.
  if(mrecv > msend)then
     do m=1,(mrecv-msend)
        zion(1:nparam,mi+m)=recvbuf(1:nparam,msend+m)
        zion0(1:nparam,mi+m)=recvbuf(nparam+1:nzion,msend+m)
     enddo
   ! tracer particle
     if( nhybrid==0 )then
        if( mrecvleft(2) > 0 .and. mrecvleft(2) > msend )then
           ntracer=mi+mrecvleft(2)-msend
        elseif( mrecvright(2) > 0 .and. mrecvright(2) > msend )then
           ntracer=mi+mrecvright(2)-msend
        endif
     endif

   ! Update value of mi, which is the # of particles remaining on local PE
     mi=mi+(mrecv-msend)

! If mrecv < msend, we still have holes in the array and we fill them by
! taking particles from the top and moving them into the holes.
  else if(mrecv < msend)then
     mtop=mi
   ! # of particles remain on local PE
     mi=mi-msend+mrecv
   ! fill the remaining holes
     lasth=msend
     do i=mrecv+1,msend
        m=kzi(i)
        if (m > mi) exit  !Break out of the DO loop if m > mi
        do while(mtop == kzi(lasth))
           mtop=mtop-1
           lasth=lasth-1
        enddo
        if( nhybrid == 0 .and. mtop == ntracer )ntracer=m
        zion(1:nparam,m)=zion(1:nparam,mtop)
        zion0(1:nparam,m)=zion0(1:nparam,mtop)
        mtop=mtop-1
        if (mtop == mi) exit  !Break out of the DO loop
     enddo
  endif

  deallocate(sendleft,sendright,recvbuf)
  m0=mi-mrecvright(1)-mrecvleft(1)+1
  goto 100
  
end subroutine shifti


