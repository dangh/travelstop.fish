exports.handler = async (event) => {
  try {
    return await getHotel(event);
  } catch (err) {
    log.info('Could not load data', err);
  }
}
