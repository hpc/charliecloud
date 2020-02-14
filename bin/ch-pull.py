#!/usr/bin/python3

# Pull and unpack an image from the open docker registry.

import argparse
import logging
import os
import sys

sys.path.insert(0, (  os.path.dirname(os.path.abspath(__file__))
                    + "/../libexec/charliecloud"))
import ch


def main():
    ap = argparse.ArgumentParser(
         formatter_class=argparse.RawDescriptionHelpFormatter,
         description='Pull and unpack image from Docker repository.',
         epilog="""\
  CH_GROW_STORAGE       default for --storage
""")
    ap.add_argument("image",
                    type=str,
                    metavar="IMAGE REFERENCE",
                    help="valid image reference")
    ap.add_argument("-s", "--storage",
                    type=str,
                    metavar="DIR",
                    help="image storage directory (default: /var/tmp/ch-grow",
                    default=os.environ.get("CH_GROW_STORAGE",
                                           "/var/tmp/ch-grow"))
    ap.add_argument("-d", "--debug",
                    action="store_true",
                    help="view debug ouput")
    if (len(sys.argv) < 2):
        ap.print_help(file=sys.stderr)
        sys.exit(1)

    args = ap.parse_args()
    if args.debug:
        ch.log_http()
    image = charliecloud.Image(args.image)
    image.unpack(args.storage)
    return 0

## Bootstrap ##

if __name__ == "__main__":
    main()
