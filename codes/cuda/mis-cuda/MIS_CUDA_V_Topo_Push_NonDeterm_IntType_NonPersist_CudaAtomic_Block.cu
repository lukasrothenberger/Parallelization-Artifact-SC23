#include <cuda/atomic>
typedef cuda::atomic<int> flag_t;
typedef int data_type;
static const int ThreadsPerBlock = 512;

#include "indigo_mis_vertex_cuda.h"

static __global__ void init(data_type* const priority, flag_t* const status, const int size)
{
  // initialize arrays
  const int v = threadIdx.x + blockIdx.x * ThreadsPerBlock;
  if (v < size)
  {
    priority[v] = hash(v + 712313887);
    status[v] = undecided;
  }
}

static __global__ void mis(const ECLgraph g, const data_type* const priority, flag_t* const status, flag_t* const goagain)
{
  // go over all the nodes
  int v = blockIdx.x;
  if (v < g.nodes) {

    if (__syncthreads_or((threadIdx.x == 0) && (status[v].load() == undecided))) {
      int i = g.nindex[v];
      // try to find a non-excluded neighbor whose priority is higher
      if (threadIdx.x == 0) {
        while ((i < g.nindex[v + 1]) && ((status[g.nlist[i]].load() == excluded) || (priority[v] > priority[g.nlist[i]]) || ((priority[v] == priority[g.nlist[i]]) && (v > g.nlist[i])))) {
          i++;
        }
      }
      if (__syncthreads_or((threadIdx.x == 0) && (i < g.nindex[v + 1]))) {
        // found such a neighbor -> status still unknown
        if (threadIdx.x == 0) {
          *goagain = 1;
        }
      } else {
        // no such neighbor -> all neighbors are "excluded" and v is "included"
        if (threadIdx.x == 0) {
          status[v].store(included);
        }
        for (int j = g.nindex[v] + threadIdx.x; j < g.nindex[v + 1]; j += ThreadsPerBlock) {
          status[g.nlist[j]].store(excluded);
        }
      }
    }
  }
}

static double GPUmis_vertex(const ECLgraph& g, data_type* const priority, int* const status)
{
  flag_t* d_goagain;
  if (cudaSuccess != cudaMalloc((void **)&d_goagain, sizeof(flag_t))) fprintf(stderr, "ERROR: could not allocate d_goagain\n");
  data_type* d_priority;
  if (cudaSuccess != cudaMalloc((void **)&d_priority, g.nodes * sizeof(data_type))) fprintf(stderr, "ERROR: could not allocate d_priority\n");
  flag_t* d_status;
  if (cudaSuccess != cudaMalloc((void **)&d_status, g.nodes * sizeof(flag_t))) fprintf(stderr, "ERROR: could not allocate d_status\n");

  const int blocks = g.nodes;

  init<<<(g.nodes + ThreadsPerBlock - 1) / ThreadsPerBlock, ThreadsPerBlock>>>(d_priority, d_status, g.nodes);

  timeval beg, end;
  gettimeofday(&beg, NULL);

  flag_t goagain;
  int iter = 0;
  do {
    iter++;
    goagain = 0;
    if (cudaSuccess != cudaMemcpy(d_goagain, &goagain, sizeof(flag_t), cudaMemcpyHostToDevice)) fprintf(stderr, "ERROR: copying of goagain to device failed\n");

    mis<<<blocks, ThreadsPerBlock>>>(g, d_priority, d_status, d_goagain);

    if (cudaSuccess != cudaMemcpy(&goagain, d_goagain, sizeof(flag_t), cudaMemcpyDeviceToHost)) fprintf(stderr, "ERROR: copying of goagain from device failed\n");
  } while (goagain);

  cudaDeviceSynchronize();
  gettimeofday(&end, NULL);
  const double runtime = end.tv_sec - beg.tv_sec + (end.tv_usec - beg.tv_usec) / 1000000.0;

  CheckCuda();
  if (cudaSuccess != cudaMemcpy(status, d_status, g.nodes * sizeof(flag_t), cudaMemcpyDeviceToHost)) fprintf(stderr, "ERROR: copying of status from device failed\n");

  // determine and print set size
  int cnt = 0;
  for (int v = 0; v < g.nodes; v++) {
    if (status[v] == included) cnt++;
  }
  printf("iterations: %d,  elements in set: %d (%.1f%%)\n", iter, cnt, 100.0 * cnt / g.nodes);

  cudaFree(d_goagain);
  cudaFree(d_status);
  cudaFree(d_priority);
  return runtime;
}
