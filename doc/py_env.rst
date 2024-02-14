:code:`CH_LOG_FILE`
  If set, append log chatter to this file, rather than standard error. This is
  useful for debugging situations where standard error is consumed or lost.

  Also sets verbose mode if not already set (equivalent to :code:`--verbose`).

:code:`CH_LOG_FESTOON`
  If set, prepend PID and timestamp to logged chatter.

:code:`CH_XATTRS`
  If set, save xattrs in the build cache and restore them when rebuilding from
  the cache (equivalent to :code:`--xattrs`).
