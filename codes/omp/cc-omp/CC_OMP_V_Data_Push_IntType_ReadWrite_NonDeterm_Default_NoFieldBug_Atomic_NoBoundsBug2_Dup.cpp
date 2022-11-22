typedef int data_type;
#include "indigo_cc_vertex_omp.h"

static void init(data_type* const label, const int size, int* const wl1, int &wlsize)
{
  // initialize label array
  for (int v = 0; v < size; v++) {
    label[v] = v;
    // initialize worklist
    wl1[v] = v;
  }
  wlsize = size;
}

static void cc_vertex_data(const ECLgraph g, data_type* const label, const int* const wl1, const int wl1size, int* const wl2, int& wl2size, const int iter)
{
  #pragma omp parallel for
  for (int idx = 0; idx < wl1size; idx ++) {
    const int src = wl1[idx];
    const data_type new_label = atomicRead(&label[src]);
    const int beg = g.nindex[src];
    const int end = g.nindex[src + 1];

    bool update = false;
    for (int i = beg; i < end; i++) {
      const int dst = g.nlist[i];

      const data_type d = atomicRead(&label[dst]);
      if (d > new_label) {
        atomicWrite(&label[dst], new_label);
        wl2[fetch_and_add(&wl2size)] = dst;
        update = true;
      }
    }
    if (update) {
      wl2[fetch_and_add(&wl2size)] = src;
    }
  }
}

static double CPUcc_vertex(const ECLgraph g, data_type* label)
{
  const int size = std::max(g.edges, g.nodes);
  int wlsize;
  int* wl1 = new int [size];
  int* wl2 = new int [size];
  int wl1size;
  int wl2size;
  timeval start, end;

  init(label, g.nodes, wl1, wl1size);

  // iterate until no more changes
  gettimeofday(&start, NULL);

  int iter = 0;
  do {
    iter++;
    wl2size = 0;

    cc_vertex_data(g, label, wl1, wl1size, wl2, wl2size, iter);

    std::swap(wl1, wl2);
    wl1size = wl2size;
  } while (wl1size > 0);

  gettimeofday(&end, NULL);
  double runtime = end.tv_sec + end.tv_usec / 1000000.0 - start.tv_sec - start.tv_usec / 1000000.0;
  printf("iterations: %d\n", iter);

  delete [] wl1;
  delete [] wl2;
  return runtime;
}