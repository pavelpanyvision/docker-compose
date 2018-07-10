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
