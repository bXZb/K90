#!/usr/bin/env python3
"""Idempotent hide_stuff port for SUSFS-patched android15-6.6 task_mmu.c / base.c."""
from pathlib import Path
import sys


def patch_task_mmu(mmu: Path) -> None:
    src = mmu.read_text()
    if "show_vma_header_prefix_fake" in src:
        print("    task_mmu.c already has hide_stuff")
        return
    if "#include <linux/string.h>" not in src:
        src = src.replace(
            "#include <linux/uaccess.h>\n",
            "#include <linux/uaccess.h>\n#include <linux/string.h>\n",
        )
    needle = (
        "\tseq_put_decimal_ull(m, \" \", ino);\n"
        "\tseq_putc(m, ' ');\n"
        "}\n"
        "\n"
        "#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
    )
    insert = (
        "\tseq_put_decimal_ull(m, \" \", ino);\n"
        "\tseq_putc(m, ' ');\n"
        "}\n"
        "\n"
        "/* ShirkNeko 69_hide_stuff: hide exec bit for jit-zygote-cache maps. */\n"
        "static void show_vma_header_prefix_fake(struct seq_file *m,\n"
        "\t\t\t\t\tunsigned long start, unsigned long end,\n"
        "\t\t\t\t\tvm_flags_t flags, unsigned long long pgoff,\n"
        "\t\t\t\t\tdev_t dev, unsigned long ino)\n"
        "{\n"
        "\tshow_vma_header_prefix(m, start, end, flags & ~VM_EXEC, pgoff, dev, ino);\n"
        "}\n"
        "\n"
        "#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
    )
    if needle not in src:
        raise SystemExit("task_mmu.c: cannot find insertion point for fake header")
    src = src.replace(needle, insert, 1)
    needle2 = (
        "#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
        "\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n"
        "#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
        "\t}\n"
        "\n"
        "\tstart = vma->vm_start;\n"
        "\tend = vma->vm_end;\n"
        "\n"
        "\t__fold_filemap_fixup_entry(&((struct proc_maps_private *)m->private)->iter, &end);\n"
        "\n"
        "\tshow_vma_header_prefix(m, start, end, flags, pgoff, dev, ino);\n"
    )
    insert2 = (
        "#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
        "\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n"
        "#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
        "\t\tif (file->f_path.dentry) {\n"
        "\t\t\tconst char *path = file->f_path.dentry->d_name.name;\n"
        "\n"
        "\t\t\tif (path && strstr(path, \"lineage\")) {\n"
        "\t\t\t\tstart = vma->vm_start;\n"
        "\t\t\t\tend = vma->vm_end;\n"
        "\t\t\t\t__fold_filemap_fixup_entry(&((struct proc_maps_private *)m->private)->iter, &end);\n"
        "\t\t\t\tshow_vma_header_prefix(m, start, end, flags, pgoff, dev, ino);\n"
        "\t\t\t\tseq_pad(m, ' ');\n"
        "\t\t\t\tseq_puts(m, \"/system/framework/framework-res.apk\");\n"
        "\t\t\t\tseq_putc(m, '\\n');\n"
        "\t\t\t\treturn;\n"
        "\t\t\t}\n"
        "\t\t\tif (path && strstr(path, \"jit-zygote-cache\")) {\n"
        "\t\t\t\tstart = vma->vm_start;\n"
        "\t\t\t\tend = vma->vm_end;\n"
        "\t\t\t\t__fold_filemap_fixup_entry(&((struct proc_maps_private *)m->private)->iter, &end);\n"
        "\t\t\t\tshow_vma_header_prefix_fake(m, start, end, flags, pgoff, dev, ino);\n"
        "\t\t\t\tgoto hide_stuff_print_path;\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\t}\n"
        "\n"
        "\tstart = vma->vm_start;\n"
        "\tend = vma->vm_end;\n"
        "\n"
        "\t__fold_filemap_fixup_entry(&((struct proc_maps_private *)m->private)->iter, &end);\n"
        "\n"
        "\tshow_vma_header_prefix(m, start, end, flags, pgoff, dev, ino);\n"
        "hide_stuff_print_path:\n"
    )
    if needle2 not in src:
        raise SystemExit("task_mmu.c: cannot find insertion point in show_map_vma")
    mmu.write_text(src.replace(needle2, insert2, 1))
    print("    patched task_mmu.c")


def patch_base(base: Path) -> None:
    src = base.read_text()
    if 'strstr(vma->vm_file->f_path.dentry->d_name.name, "lineage")' in src:
        print("    base.c already has hide_stuff")
        return
    old = (
        "\trc = -ENOENT;\n"
        "\tvma = find_exact_vma(mm, vm_start, vm_end);\n"
        "\tif (vma && vma->vm_file) {\n"
        "\t\t*path = vma->vm_file->f_path;\n"
        "\t\tpath_get(path);\n"
        "\t\trc = 0;\n"
        "\t}\n"
        "\tmmap_read_unlock(mm);\n"
    )
    new = (
        "\trc = -ENOENT;\n"
        "\tvma = find_exact_vma(mm, vm_start, vm_end);\n"
        "\tif (vma && vma->vm_file) {\n"
        "\t\tif (vma->vm_file->f_path.dentry &&\n"
        "\t\t    strstr(vma->vm_file->f_path.dentry->d_name.name, \"lineage\")) {\n"
        "\t\t\trc = kern_path(\"/system/framework/framework-res.apk\", LOOKUP_FOLLOW, path);\n"
        "\t\t} else {\n"
        "\t\t\t*path = vma->vm_file->f_path;\n"
        "\t\t\tpath_get(path);\n"
        "\t\t\trc = 0;\n"
        "\t\t}\n"
        "\t}\n"
        "\tmmap_read_unlock(mm);\n"
    )
    if old not in src:
        raise SystemExit("base.c: cannot find map_files path lookup to patch")
    base.write_text(src.replace(old, new, 1))
    print("    patched base.c")


def main() -> None:
    common = Path(sys.argv[1])
    patch_task_mmu(common / "fs/proc/task_mmu.c")
    patch_base(common / "fs/proc/base.c")


if __name__ == "__main__":
    main()
