import sys
from pathlib import Path
_root = str(Path(__file__).resolve().parent.parent.parent)
if _root not in sys.path:
    sys.path.insert(0, _root)

from datetime import datetime
from backend.core.timeutil import IST, logical_date


def test_logical_date_boundaries():
    # 2026-10-07 03:59:59 IST -> belongs to 2026-10-06
    t1 = datetime(2026, 10, 7, 3, 59, 59, tzinfo=IST)
    assert logical_date(t1) == "2026-10-06"

    # 2026-10-07 04:00:00 IST -> belongs to 2026-10-07
    t2 = datetime(2026, 10, 7, 4, 0, 0, tzinfo=IST)
    assert logical_date(t2) == "2026-10-07"

    # 2026-10-07 23:59:59 IST -> belongs to 2026-10-07
    t3 = datetime(2026, 10, 7, 23, 59, 59, tzinfo=IST)
    assert logical_date(t3) == "2026-10-07"

    # 2026-10-07 00:00:00 IST (midnight) -> belongs to 2026-10-06
    t4 = datetime(2026, 10, 7, 0, 0, 0, tzinfo=IST)
    assert logical_date(t4) == "2026-10-06"

    # 2026-10-07 01:30:00 IST (after midnight) -> belongs to 2026-10-06
    t5 = datetime(2026, 10, 7, 1, 30, 0, tzinfo=IST)
    assert logical_date(t5) == "2026-10-06"


if __name__ == "__main__":
    test_logical_date_boundaries()
    print("ALL TIMEUTIL BOUNDARY TESTS PASSED!")
