exports.handler = async (event) => {
  try {
    return await go(event);
  } catch (err) {
    log.error('module level failure', err);
  }
}
