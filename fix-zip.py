#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
from pathlib import Path

# Note: LE encoding
ZIP_LOCAL_HDR_SIG = b'\x50\x4b\x03\x04'
ZIP_END_CENTRAL_HDR_SIG = b'\x50\x4b\x05\x06'
CORRECT_OFFSET = b'\xff\xff\xff\xff'
ZIP64_END_CENTRAL_LOC_HDR_SIG = b'\x50\x4b\x06\x07'

def fix_zip(filepath: Path, dry_run: bool):
   try:
      with open(filepath, 'r+b') as f:
         # ZIP signature check
         if f.read(4) != ZIP_LOCAL_HDR_SIG:
            raise ValueError(f'Wrong Zip signature at start of {filepath}')

         f.seek(-42, os.SEEK_END)
         data = f.read(42)

         # EOCD signature check
         if data[20:24] != ZIP_END_CENTRAL_HDR_SIG:
            raise ValueError(f'Cannot find Zip signature at end of {filepath}')
         
         # EOCD offset check
         if data[36:40] != CORRECT_OFFSET:
            raise ValueError(f'Bad offset at the end of {filepath}')

         # ZIP64 signature check
         if data[:4] != ZIP64_END_CENTRAL_LOC_HDR_SIG:
            raise ValueError(f'Cannot find ZIP64 signature at end of {filepath}')
         
         # Apply correction
         match data[16:20]:
            case b'\x00\x00\x00\x00':
               if dry_run:
                  print('(dry-run)', end=' ')
               else:
                  f.seek(-42 + 16, os.SEEK_END)
                  f.write(b'\x01\x00\x00\x00')
               print(f'Correction applied: "Total Number of Disks" set to 1 for {filepath}')
            case b'\x01\x00\x00\x00':
               print(f'Nothing to do: "Total Number of Disks" field is already set to 1 for {filepath}')
            case _:
               raise ValueError(f'Unknown "Total Number of Disks" value in {filepath}')
            
   except (FileNotFoundError, ValueError) as err:
      print(err)
      print('File skipped!')


if __name__ == '__main__':
   parser = argparse.ArgumentParser(
      prog='fix-zip',
      description='''
      Fix OneDrive/Windows Zip files larger than 4GiB that have an invalid 
      'Total Number of Disks' field in the 'ZIP64 End Central Directory Locator'. 
      The value in this field should be 1, but OneDrive/Windows sets it to 0. This
      makes it difficult to work with these files using standard unzip utilities.
      '''
   )
   parser.add_argument(
      '--dry-run', 
      action='store_true', 
      help='perform a trial run with no changes made'
   )
   parser.add_argument(
      'files', 
      type=Path, 
      metavar='ZIP_PATH', 
      nargs='+',
      help='Paths of the ZIP files'
   )
   args = parser.parse_args()

   for path in args.file:
      fix_zip(path, args.dry_run)
