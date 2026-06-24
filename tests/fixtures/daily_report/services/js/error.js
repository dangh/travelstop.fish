exports.handler = async (event) => {
  try {
    return await getHotel(event);
  } catch (err) {
    log.error('Failed to fetch hotel', err);
    throw err;
  }
}
