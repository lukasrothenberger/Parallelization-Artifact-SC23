typedef unsigned int data_type;
#include "indigo_mis_vertex_omp.h"

static void init(data_type* const priority, unsigned char* const status, unsigned char* const status_n, const int size, int* const wl1, int &wlsize)
{
  // initialize arrays
  for (int v = 0; v < size; v++)
  {
    priority[v] = hash(v + 712313887);
    status[v] = undecided;
    status_n[v] = undecided;

    // initialize worklist
    wl1[v] = v;
  }
  wlsize = size;
}

static void mis(const ECLgraph& g, const data_type* const priority, unsigned char* const status, unsigned char* const status_n, const int* const wl1, const int wl1size, int* const wl2, int& wl2size)
{
  #pragma omp parallel for
  for (int w = 0; w < wl1size; w++) {
    // go over all nodes in WL
    int v = wl1[w];
    if (atomicRead(&status[v]) == undecided) {
      int i = g.nindex[v];
      // try to find a non-excluded neighbor whose priority is higher
      while ((i < g.nindex[v + 1]) && ((atomicRead(&status[g.nlist[i]]) == excluded) || (priority[v] > priority[g.nlist[i]]) || ((priority[v] == priority[g.nlist[i]]) && (v > g.nlist[i])))) {
        i++;
      }
      if (i < g.nindex[v + 1]) {
        // found such a neighbor -> status still unknown
        wl2[criticalAdd(&wl2size, 1)] = v;
      } else {
        // no such neighbor -> all neighbors are "excluded" and v is "included"
        status_n[v] = included;
        for (int i = g.nindex[v]; i < g.nindex[v + 1]; i++) {
          status_n[g.nlist[i]] = excluded;
        }
      }
    }
  }
}

static double OMPmis_vertex(const ECLgraph& g, data_type* const priority, unsigned char* status)
{
  unsigned char* status_new = new unsigned char [g.nodes];
  int* wl1 = new int [g.nodes];
  int* wl2 = new int [g.nodes];
  int wl1size;
  int wl2size;

  init(priority, status, status_new, g.nodes, wl1, wl1size);

  timeval beg, end;
  gettimeofday(&beg, NULL);

  int iter = 0;
  do {
    iter++;
    wl2size = 0;

    mis(g, priority, status, status_new, wl1, wl1size, wl2, wl2size);

    std::copy(status_new, status_new + g.nodes, status);

    std::swap(wl1, wl2);
    wl1size = wl2size;
  } while (wl1size > 0);

  gettimeofday(&end, NULL);
  const double runtime = end.tv_sec - beg.tv_sec + (end.tv_usec - beg.tv_usec) / 1000000.0;

  // determine and print set size
  int cnt = 0;
  for (int v = 0; v < g.nodes; v++) {
    if (status[v] == included) cnt++;
  }
  printf("iterations: %d,  elements in set: %d (%.1f%%)\n", iter, cnt, 100.0 * cnt / g.nodes);

  delete [] status_new;
  delete [] wl1;
  delete [] wl2;
  return runtime;
}