/// What can be attempted on a link, in Connection's words, so a failure
/// names the operation it answers without borrowing the platform's names.
enum LinkOperation {
  open,
  close,
  negotiateMtu,
  readWritePayloadLimit,
  readSignalStrength,
  readBondState,
  followBondState,
  bond,
  removeBond,
  readPhy,
  readTransmitPhy,
  readReceivePhy,
  followPhy,
  requestPhy,
}
