import cobs
import unittest
import random
import sequtils
import strformat


proc doEncodeTest(input, expected: seq[byte]) =
  let res = input.encode()
  try:
    assert res == expected
  except AssertionError:
    echo &"Input: {input}\nResult: {res}\nExpected: {expected}"
    raise


proc doDecodeTest(input, expected: seq[byte]) =
  let res = input.decode()
  try:
    assert res == expected
  except AssertionError:
    echo &"Input: {input}\nResult: {res}\nExpected: {expected}"
    raise


proc randomIntSequence(length: int, allowZero: bool=true): seq[byte] =
  result = newSeq[byte](length)
  for i in 0..<length:
    if allowZero:
      result[i] = rand(0..255).byte
    else:
      result[i] = rand(1..255).byte


proc byteSeq(s: openarray[SomeInteger]): seq[uint8] =
  result = map(s, proc(x: SomeInteger): uint8 = x.uint8)


suite "Test Cobs Encoding":
  test "Single Zero":
    doEncodeTest(byteSeq([0]), byteSeq([1, 1, 0]))

  test "Double Zero":
    doEncodeTest(byteSeq([0, 0]), byteSeq([1, 1, 1, 0]))

  test "Sequence with zero in the middle":
    doEncodeTest(byteSeq([11, 22, 0, 33]), byteSeq([3, 11, 22, 2, 33, 0]))

  test "Sequece with no zeros":
    doEncodeTest(byteSeq([11, 22, 33, 44]), byteSeq([05, 11, 22, 33, 44, 00]))

  test "Lots of trailing zeros":
    doEncodeTest(byteSeq([11, 00, 00, 00]), byteSeq([02, 11, 01, 01, 01, 00]))


suite "Test Cobs Decoding":
  test "Single Zero":
    doDecodeTest(byteSeq([1, 1, 0]), byteSeq([0]))

  test "Double Zero":
    doDecodeTest(byteSeq([1, 1, 1, 0]), byteSeq([0, 0]))

  test "Sequence with zero in the middle":
    doDecodeTest(byteSeq([3, 11, 22, 2, 33, 0]), byteSeq([11, 22, 0, 33]))

  test "Sequece with no zeros":
    doDecodeTest(byteSeq([05, 11, 22, 33, 44, 00]), byteSeq([11, 22, 33, 44]))

  test "Lots of trailing zeros":
    doDecodeTest(byteSeq([02, 11, 01, 01, 01, 00]), byteSeq([11, 00, 00, 00]))

  test "Bad Decode (missing end delimiter)":
    expect(CobsDecodeError):
      doDecodeTest(byteSeq([1, 1]), byteSeq([0]))

  test "Bad Decode (Incorrect delimiter distance)":
    expect(CobsDecodeError):
      doDecodeTest(byteSeq([3, 11, 22, 3, 33, 0]), byteSeq([11, 22, 0, 33]))


suite "Test round trip Encoding/Decoding":
  randomize()
  test "Simple fixed size round trip":
    let input = byteSeq([11, 22, 0, 33])
    assert(input.encode().decode() == input)

  test ">255 bytes, no zero at end":
    ## Cobs max is 255 bytes between zeros
    var input = randomIntSequence(257, false).byteSeq()
    let encoded = input.encode()
    let decoded = encoded.decode()
    try:
      assert(decoded == input)
    except AssertionError:
      echo input
      echo encoded
      echo decoded
      raise

  test ">255 bytes, zero at end":
    var input = randomIntSequence(257, false).byteSeq()
    input.add(0)
    let encoded = input.encode()
    let decoded = encoded.decode()
    try:
      assert(decoded == input)
    except AssertionError:
      echo input
      echo encoded
      echo decoded
      raise
