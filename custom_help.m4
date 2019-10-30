m4_cleardivert([HELP_BEGIN])dnl
m4_cleardivert([HELP_CANON])dnl
m4_cleardivert([HELP_ENABLE])dnl
m4_cleardivert([HELP_WITH])dnl
m4_cleardivert([HELP_VAR])dnl
m4_cleardivert([HELP_VAR_END])dnl
m4_cleardivert([HELP_END])dnl
m4_divert_push([HELP_BEGIN])dnl
  cat <<_ACEOF
Hello World
_ACEOF
m4_divert_pop([HELP_BEGIN])dnl
m4_divert_push([HELP_END])dnl
exit 0
m4_divert_pop([HELP_END])dnl
