exports.handler = async (event) => {
  try {
    await a();
  } catch (e) {
    if (e) {
      log.error('deep nested message');
    }
  }
}
