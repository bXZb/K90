#!/usr/bin/env python3
"""Test-only hide_stuff for SUSFS-patched android15-6.6-2026-07 (6.6.139).

6.6.139 show_map_vma uses VMA_PAD_START and __VM_NO_COMPAT. The mainline
port in scripts/lib/apply_hide_stuff.py is pinned to 6.6.77 and must stay
untouched. Missing needles skip with a warning so the test kernel still builds.
"""
from pathlib import Path
import sys

FAKE_FN = """/* ShirkNeko 69_hide_stuff: hide exec bit for jit-zygote-cache maps. */
static void show_vma_header_prefix_fake(struct seq_file *m,
					unsigned long start, unsigned long end,
					vm_flags_t flags, unsigned long long pgoff,
					dev_t dev, unsigned long ino)
{
	show_vma_header_prefix(m, start, end, flags & ~VM_EXEC, pgoff, dev, ino);
}

"""

# Inserted immediately before show_vma_header_prefix() in show_map_vma.
HIDE_CALL = """	if (file && file->f_path.dentry) {
		const char *path = file->f_path.dentry->d_name.name;

		if (path && strstr(path, "lineage")) {
			show_vma_header_prefix(m, start, end, flags, pgoff, dev, ino);
			seq_pad(m, ' ');
			seq_puts(m, "/system/framework/framework-res.apk");
			seq_putc(m, '\\n');
			return;
		}
		if (path && strstr(path, "jit-zygote-cache")) {
			show_vma_header_prefix_fake(m, start, end, flags, pgoff, dev, ino);
			goto hide_stuff_print_path;
		}
	}

"""


def _skip(msg: str) -> None:
    print(f"    skip hide_stuff: {msg}")


def patch_task_mmu(mmu: Path) -> None:
    src = mmu.read_text()
    if "show_vma_header_prefix_fake" in src and "hide_stuff_print_path" in src:
        print("    task_mmu.c already has hide_stuff")
        return
    if "#include <linux/string.h>" not in src:
        if "#include <linux/uaccess.h>\n" in src:
            src = src.replace(
                "#include <linux/uaccess.h>\n",
                "#include <linux/uaccess.h>\n#include <linux/string.h>\n",
                1,
            )
        else:
            src = "#include <linux/string.h>\n" + src

    if "show_vma_header_prefix_fake" not in src:
        header_end = (
            "\tseq_put_decimal_ull(m, \" \", ino);\n"
            "\tseq_putc(m, ' ');\n"
            "}\n"
        )
        idx = src.find(header_end)
        if idx < 0:
            _skip("task_mmu.c: cannot find show_vma_header_prefix end")
            return
        insert_at = idx + len(header_end)
        src = src[:insert_at] + "\n" + FAKE_FN + src[insert_at:]

    fold_header = (
        "\t__fold_filemap_fixup_entry(&((struct proc_maps_private *)m->private)->iter, &end);\n"
        "\n"
        "\tshow_vma_header_prefix(m, start, end, flags, pgoff, dev, ino);\n"
    )
    if fold_header not in src:
        _skip("task_mmu.c: cannot find 6.6.139 fold+header in show_map_vma")
        return
    replacement = (
        "\t__fold_filemap_fixup_entry(&((struct proc_maps_private *)m->private)->iter, &end);\n"
        "\n"
        + HIDE_CALL
        + "\tshow_vma_header_prefix(m, start, end, flags, pgoff, dev, ino);\n"
        "hide_stuff_print_path:\n"
    )
    src = src.replace(fold_header, replacement, 1)
    mmu.write_text(src)
    print("    patched task_mmu.c (6.6.139)")


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
        _skip("base.c: cannot find map_files path lookup")
        return
    base.write_text(src.replace(old, new, 1))
    print("    patched base.c")


def main() -> None:
    common = Path(sys.argv[1])
    patch_task_mmu(common / "fs/proc/task_mmu.c")
    patch_base(common / "fs/proc/base.c")


if __name__ == "__main__":
    main()
