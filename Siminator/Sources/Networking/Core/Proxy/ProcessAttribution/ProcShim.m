//
//  ProcShim.m
//  Siminator
//
//  Created by Mikolaj Zawada on 09/06/2026.
//

#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include "ProcShim.h"

int sim_proc_listallpids(void *buffer, int buffersize) {
    return proc_listallpids(buffer, buffersize);
}
int sim_proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize) {
    return proc_pidinfo(pid, flavor, arg, buffer, buffersize);
}
int sim_proc_pidfdinfo(int pid, int fd, int flavor, void *buffer, int buffersize) {
    return proc_pidfdinfo(pid, fd, flavor, buffer, buffersize);
}
int sim_proc_pidpath(int pid, void *buffer, uint32_t buffersize) {
    return proc_pidpath(pid, buffer, buffersize);
}
uint16_t sim_ntohs(uint16_t value) {
    return ntohs(value);
}
int sim_proc_pidpathinfo_maxsize(void) {
    return PROC_PIDPATHINFO_MAXSIZE;
}
