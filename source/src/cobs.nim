# Copyright 2018 KeyMe Inc
# Consistent overhead byte stuffing for Nim

## Consistent Overhead Byte Stuffing (COBS) is a framing method for
## binary streams and is useful any time you need to send binary
## datagrams over a stream interface (TCP socket / Serial Port / Etc).
## In a nutshell, COBS works by stripping all `delimiter` bytes
## (usually `0x00`) out of a binary packet and places a single
## `delimiter` at the end, allowing recipients to simply read from the
## stream until a `delimiter` is encountered (effectively allowing a
## 'readline' like interface for binary data). The encoding/decoding
## are very fast and encoding is guaranteed to only add 1 + max(1, (len/255))
## overhead bytes (making decoding extremely deterministic). For an
## in-depth breakdown of the algorithm, please see
## https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing

import strformat

type
  CobsDecodeError* = object of Exception

const
  MaxPacketSize = 255


iterator splitOn[T](s: openarray[T], delim: T): seq[T] =
  ## Iterates over an array, yielding slices of all data in
  ## between `delim`. In cases where delimiters are at the start
  ## of the buffer (or back to back), an empty sequence will be
  ## yielded.

  ## e.g. delim == zero: @[0, 0] => @[] @[]
  ## e.g. delim == zero: @[1, 2, 0, 3, 4] => @[1, 2] @[3, 4]
  var pos = 0
  var last = 0
  while pos <= s.high:
    if s[pos] == delim:
      yield s[last..pos - 1]
      # Skip over the delimiter
      last = pos + 1
    inc(pos)
  yield s[last..s.high]

iterator chunksOf[T](s: openarray[T], size: int): seq[T] =
  ## Yields even sized chunks of the input array. If there are an
  ## uneven number of units at the end of the buffer, the last chunk
  ## will simply be the remainder.

  ## e.g. [1..10].chunksOf(3) => @[1, 2, 3] @[4, 5, 6] @[7, 8, 9] @[10]
  var consumed = 0

  if s.high == -1:
    # Yield an empty seq for empty input
    yield @[]
  else:
    while consumed <= s.high:
      let sliceEnd = min(s.high, consumed + size - 1)
      yield s[consumed..sliceEnd]
      consumed += size

proc encode*(buf: openarray[byte], delimiter: byte=0): seq[byte] =
  ## Encodes `buf` using COBS, removing all `delimiter` bytes from
  ## the input buffer and placing a single `delimiter` byte at the end
  result = @[]

  for group in buf.splitOn(delimiter):
    for chunk in group.chunksOf(MaxPacketSize - 1):
      result.add((len(chunk) + 1).byte)
      result &= chunk

  result.add(0)

proc decode*(buf: openarray[byte], delimiter: byte=0): seq[byte] {.raises:[CobsDecodeError].} =
  ## Decodes COBS encoded `buf`, restoring all `delimiter`
  ## bytes and stripping overhead bytes.
  if buf[^1] != delimiter:
    raise newException(CobsDecodeError,
                       &"Buffer did not contain a {delimiter} at the end")
  result = @[]
  var pos = 0
  while pos < buf.high:
    let chunkLen = buf[pos]

    # A position beyond the end of the input buffer is an error
    if (pos + chunkLen.int) > buf.high:
      raise newException(CobsDecodeError, "Corrupt Data")

    result &= buf[(pos + 1)..(pos + chunkLen.int - 1)]
    pos = pos + chunkLen.int

    # If the chunk length == MaxPacketSize, this indicates an overhead
    # byte was added to delimit a segment > MaxPacketSize and as a
    # result, we shouldn't include the delimiter in this position
    if pos < buf.high and chunkLen < MaxPacketSize:
      result.add(delimiter.byte)
