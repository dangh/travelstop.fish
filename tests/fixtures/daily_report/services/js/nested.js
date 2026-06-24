exports.handler = async (event) => {
  try {
    await a();
  } catch (e) {
    log.error('first error here');
  }
  try {
    await b();
  } catch (e) {
    log.error('second error here');
  }
}
