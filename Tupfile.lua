if tup.getconfig("NO_FASM") ~= "" then return end
tup.rule("kterm.asm", "fasm %f %o " .. tup.getconfig("KPACK_CMD"), "kterm")
