/* eslint-disable */
db.createCollection("ignores");
cursor = db.suspects.find({ignore: true});
while (cursor.hasNext()){
  ignore = cursor.next()
  delete ignore.ignore
  delete ignore.description
  delete ignore.addedImages
  db.ignores.insert(ignore)
}

db.suspects.remove({ignore: true})
db.detections.remove({label: 'ignored'})
db.suspect_groups.update({_id: ObjectId("000000000000000000000002")}, { $set:{title:"Low Quality Images"}}

detectionsCursor = db.detections.find();
while (detectionsCursor.hasNext()) {
  detection = detectionsCursor.next();
  if (!detection.images) continue;

  detection.zoom_in_images = detection.images.filter(function(i){return !i.includes('Large');});
  detection.zoom_out_images = detection.images.filter(function(i){return i.includes('Large');});
  delete detection.images;
  db.detections.save(detection);
}
