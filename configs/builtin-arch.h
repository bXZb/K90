#ifndef __KSU_H_ARCH
#define __KSU_H_ARCH

/*
 * Missing from SukiSU-Ultra builtin after 486ad6f29 (#include "arch.h" in
 * kernel_includes.h without the file). Same content as tiann/KernelSU
 * kernel/include/arch.h and SukiSU-Ultra#974. Drop this copy once builtin
 * ships kernel/arch.h.
 */

#include <linux/version.h>

#if defined(__aarch64__)

#define __PT_PARM1_REG regs[0]
#define __PT_PARM2_REG regs[1]
#define __PT_PARM3_REG regs[2]
#define __PT_SYSCALL_PARM4_REG regs[3]
#define __PT_CCALL_PARM4_REG regs[3]
#define __PT_PARM5_REG regs[4]
#define __PT_PARM6_REG regs[5]
#define __PT_RET_REG regs[30]
#define __PT_FP_REG regs[29] /* Works only with CONFIG_FRAME_POINTER */
#define __PT_RC_REG regs[0]
#define __PT_SP_REG sp
#define __PT_IP_REG pc
#define __PT_ORIG_SYSCALL_REG regs[8]

#define REBOOT_SYMBOL "__arm64_sys_reboot"
#define SYS_READ_SYMBOL "__arm64_sys_read"
#define SYS_EXECVE_SYMBOL "__arm64_sys_execve"
#define SYS_FSTAT_SYMBOL "__arm64_sys_newfstat"

#elif defined(__x86_64__)

#define __PT_PARM1_REG di
#define __PT_PARM2_REG si
#define __PT_PARM3_REG dx
#define __PT_SYSCALL_PARM4_REG r10
#define __PT_CCALL_PARM4_REG cx
#define __PT_PARM5_REG r8
#define __PT_PARM6_REG r9
#define __PT_RET_REG sp
#define __PT_FP_REG bp
#define __PT_RC_REG ax
#define __PT_SP_REG sp
#define __PT_IP_REG ip
#define __PT_ORIG_SYSCALL_REG orig_ax
#define REBOOT_SYMBOL "__x64_sys_reboot"
#define SYS_READ_SYMBOL "__x64_sys_read"
#define SYS_EXECVE_SYMBOL "__x64_sys_execve"
#define SYS_FSTAT_SYMBOL "__x64_sys_newfstat"

#elif defined(__riscv)

#define __PT_PARM1_REG a0
#define __PT_SYSCALL_PARM1_REG orig_a0
#define __PT_PARM2_REG a1
#define __PT_PARM3_REG a2
#define __PT_SYSCALL_PARM4_REG a3
#define __PT_CCALL_PARM4_REG a3
#define __PT_PARM5_REG a4
#define __PT_PARM6_REG a5
#define __PT_RET_REG ra
#define __PT_FP_REG s0
#define __PT_RC_REG a0
#define __PT_SP_REG sp
#define __PT_IP_REG epc
#define __PT_ORIG_SYSCALL_REG a7

#define REBOOT_SYMBOL "__riscv_sys_reboot"
#define SYS_READ_SYMBOL "__riscv_sys_read"
#define SYS_EXECVE_SYMBOL "__riscv_sys_execve"
#define SYS_FSTAT_SYMBOL "__riscv_sys_newfstat"

#else
#error "Unsupported arch"
#endif

#ifndef __PT_REGS_CAST
#define __PT_REGS_CAST(x) (x)
#endif

#define PT_REGS_PARM1(x) (__PT_REGS_CAST(x)->__PT_PARM1_REG)
#ifndef __PT_SYSCALL_PARM1_REG
#define __PT_SYSCALL_PARM1_REG __PT_PARM1_REG
#endif
#define PT_REGS_SYSCALL_PARM1(x) (__PT_REGS_CAST(x)->__PT_SYSCALL_PARM1_REG)
#define PT_REGS_PARM2(x) (__PT_REGS_CAST(x)->__PT_PARM2_REG)
#define PT_REGS_PARM3(x) (__PT_REGS_CAST(x)->__PT_PARM3_REG)
#define PT_REGS_SYSCALL_PARM4(x) (__PT_REGS_CAST(x)->__PT_SYSCALL_PARM4_REG)
#define PT_REGS_CCALL_PARM4(x) (__PT_REGS_CAST(x)->__PT_CCALL_PARM4_REG)
#define PT_REGS_PARM5(x) (__PT_REGS_CAST(x)->__PT_PARM5_REG)
#define PT_REGS_PARM6(x) (__PT_REGS_CAST(x)->__PT_PARM6_REG)
#define PT_REGS_RET(x) (__PT_REGS_CAST(x)->__PT_RET_REG)
#define PT_REGS_FP(x) (__PT_REGS_CAST(x)->__PT_FP_REG)
#define PT_REGS_RC(x) (__PT_REGS_CAST(x)->__PT_RC_REG)
#define PT_REGS_SP(x) (__PT_REGS_CAST(x)->__PT_SP_REG)
#define PT_REGS_IP(x) (__PT_REGS_CAST(x)->__PT_IP_REG)
#define PT_REGS_ORIG_SYSCALL(x) (__PT_REGS_CAST(x)->__PT_ORIG_SYSCALL_REG)

#define PT_REAL_REGS(regs) ((struct pt_regs *)PT_REGS_PARM1(regs))

#endif
