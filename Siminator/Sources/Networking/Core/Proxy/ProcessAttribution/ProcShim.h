// ProcShim.h
#include <stdint.h>
#include <libproc.h>
#include <sys/proc_info.h>

int sim_proc_listallpids(void *buffer, int buffersize);
int sim_proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
int sim_proc_pidfdinfo(int pid, int fd, int flavor, void *buffer, int buffersize);
int sim_proc_pidpath(int pid, void *buffer, uint32_t buffersize);
uint16_t sim_ntohs(uint16_t value);
int sim_proc_pidpathinfo_maxsize(void);
