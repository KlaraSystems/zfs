Something like the following needs to be added to tests/runfiles/common.run

[tests/functional/rorw]
tests = ['upgrade_rorw_001.ksh', 'upgrade_rorw_002.ksh',
    'upgrade_rorw_003.ksh', 'upgrade_rorw_004.ksh', 'upgrade_rorw_005.ksh',
    'upgrade_rorw_006.ksh', 'upgrade_rorw_007.ksh', 'upgrade_rorw_008.ksh',
    'upgrade_rorw_009.ksh', 'upgrade_rorw_010.ksh', 'upgrade_rorw_011.ksh',
    'upgrade_rorw_012.ksh', 'upgrade_rorw_013.ksh', 'upgrade_rorw_014.ksh',
    'upgrade_rorw_015.ksh']
tags = ['functional', 'rorw']

Also, note that all the .ksh files need to have execute permission, or the
tests are removed for validation failure.

reader.c builds a standalone tool which takes a non-empty file as an
argument, and repeatedly (4KHz) reads the first byte.  If it encounters
a read error, it exits with an error result.  If it receives any input
on stdin, it exits with a zero result.  It's intended for testing whether
the ro->rw upgrade interrupts any readers.

