"""six is a transitive dep that the graphless pylock never names as one."""

import dateutil.tz
import six

print(dateutil.tz.UTC, six.__version__)
