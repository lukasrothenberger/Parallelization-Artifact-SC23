typedef float score_type;
#include "indigo_pr_cuda.h"

__global__ void contrib(int nodes, score_type* scores, int* degree, score_type* outgoing_contrib)
{
  int tid = blockIdx.x;
  for (int src = tid; src < nodes; src += gridDim.x) {
    outgoing_contrib[src] = scores[src] / degree[src];
  }
}

__global__ void pull(int nodes, const int* const __restrict__ nindex, const int* const __restrict__ nlist, score_type* scores, score_type* outgoing_contrib, score_type* diff, score_type base_score, int* degree)
{
  const int lane = threadIdx.x % WarpSize;
  __shared__ score_type buffer[WarpSize];
  score_type error = 0;
  int tid = blockIdx.x;
  for (int src = tid; src < nodes; src += gridDim.x) {
    score_type incoming_total = 0;
    const int beg = nindex[src];
    const int end = nindex[src + 1];
    for (int i = beg + threadIdx.x; i < end; i += ThreadsPerBlock) {
      int dst = nlist[i];
      incoming_total +=  scores[dst] / degree[dst];
    }
    __syncthreads();
    incoming_total = block_sum_reduction(incoming_total, buffer);
    if (threadIdx.x == 0) {
      score_type old_score = scores[src];
      const score_type value = base_score + kDamp * incoming_total;
      scores[src] = value;
      error = fabs(value - old_score);
    }
    error = block_sum_reduction(error, buffer);
    if (threadIdx.x == 0) atomicAdd(diff, error);
  }
}

void PR_GPU(const ECLgraph g, score_type *scores, int* degree)
{
  ECLgraph d_g = g;
  int *d_degree;
  score_type *d_scores, *d_sums, *d_contrib;
  score_type *d_diff, h_diff;
  const int ThreadsBound = GPUinfo(0);
  const int blocks = ThreadsBound / ThreadsPerBlock;
  // allocate device memory
  cudaMalloc((void **)&d_degree, g.nodes * sizeof(int));
  cudaMalloc((void **)&d_scores, g.nodes * sizeof(score_type));
  cudaMalloc((void **)&d_sums, g.nodes * sizeof(score_type));
  cudaMalloc((void **)&d_contrib, g.nodes * sizeof(score_type));
  cudaMalloc((void **)&d_diff, sizeof(score_type));
  if (cudaSuccess != cudaMalloc((void **)&d_g.nindex, (g.nodes + 1) * sizeof(int))) fprintf(stderr, "ERROR: could not allocate nindex\n");
  if (cudaSuccess != cudaMalloc((void **)&d_g.nlist, g.edges * sizeof(int))) fprintf(stderr, "ERROR: could not allocate nlist\n");
  // copy data to device
  cudaMemcpy(d_degree, degree, g.nodes * sizeof(int), cudaMemcpyHostToDevice);
  cudaMemcpy(d_scores, scores, g.nodes * sizeof(score_type), cudaMemcpyHostToDevice);
  if (cudaSuccess != cudaMemcpy(d_g.nindex, g.nindex, (g.nodes + 1) * sizeof(int), cudaMemcpyHostToDevice)) fprintf(stderr, "ERROR: copying of index to device failed\n");
  if (cudaSuccess != cudaMemcpy(d_g.nlist, g.nlist, g.edges * sizeof(int), cudaMemcpyHostToDevice)) fprintf(stderr, "ERROR: copying of nlist to device failed\n");
  const score_type base_score = (1.0f - kDamp) / (score_type)g.nodes;
  // timer
  const int runs = 1;
  timeval start, end;
  double runtimes[runs];
  for (int i = 0; i < runs; i++) {
    int iter = 0;
    gettimeofday(&start, NULL);
    do {
      iter++;
      h_diff = 0;
      if (cudaSuccess != cudaMemcpy(d_diff, &h_diff, sizeof(score_type), cudaMemcpyHostToDevice)) fprintf(stderr, "ERROR: copying of h_diff to device failed\n");
      pull<<<blocks, ThreadsPerBlock>>>(g.nodes, d_g.nindex, d_g.nlist, d_scores, d_contrib, d_diff, base_score, d_degree);
      if (cudaSuccess != cudaMemcpy(&h_diff, d_diff, sizeof(score_type), cudaMemcpyDeviceToHost)) fprintf(stderr, "ERROR: copying of d_diff from device failed\n");
    } while (h_diff > EPSILON && iter < MAX_ITER);
    cudaDeviceSynchronize();
    gettimeofday(&end, NULL);
    runtimes[i] = end.tv_sec + end.tv_usec / 1000000.0 - start.tv_sec - start.tv_usec / 1000000.0;
    printf("GPU iterations = %d.\n", iter);
  }
  const double med = median(runtimes, runs);
  printf("GPU runtime: %.6fs\n\n", med);
  printf("Throughput: %.6f gigaedges/s\n", 0.000000001 * g.edges / med);
  if (cudaSuccess != cudaMemcpy(scores, d_scores, g.nodes * sizeof(score_type), cudaMemcpyDeviceToHost)) fprintf(stderr, "ERROR: copying of d_scores from device failed\n");
  cudaFree(d_degree);
  cudaFree(d_scores);
  cudaFree(d_sums);
  cudaFree(d_contrib);
  cudaFree(d_diff);
  return;
}
