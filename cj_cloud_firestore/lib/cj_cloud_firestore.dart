library cj_cloud_firestore;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

class CjCloudFirestore {

  CjCloudFirestore.init(String realm) {
    CjCloudFirestore._realm = realm;
  }

  CjCloudFirestore();

  static late final String _realm;  
  static DocumentSnapshot? userDocSnapshot;
  static DocumentReference? userDocReference;

  FirebaseFirestore _store = FirebaseFirestore.instance;

  FirebaseFirestore get store => _store;
  WriteBatch get batch => _store.batch();  

  String collectionNameFromTableName (String tableName) {
        
    String collName = "";
    final String pattern = r"^[a-z]+$"; 
    final regexp = RegExp(pattern);

    tableName.split("").forEach((char) {
        
      final lCase = char.toLowerCase();

      // if (/[a-z]/.test(char)) {
      if (regexp.hasMatch(char)) {
          collName += lCase;
      } else {
          collName += collName.isNotEmpty ? "_" + lCase: lCase;
      }
    });

    return collName;
  } 

  String _docOrCollectionPath(String tableName, {String? docId}) {
    if (docId != null) {
      docId = "$docId";
    } else {
      docId = "";
    }

    final isComplex = tableName.indexOf("/") >= 0;

    String collName = "";

    if (isComplex) {
      tableName.split("/").asMap().forEach((k, v) {
        if (k % 2 == 1) {
          // If it's an odd index, it's a document id, leave unchanged.
          collName += "/" + v;
        } else {
          // If it is an even index, it's a collection name, append the realm suffix only if it is the root collection.
          String loopCollName = collectionNameFromTableName(v);

          if (k > 0) {
            print("$v is a sub collection");
            collName += "/" + loopCollName;
          } else {
            print("$v is the root collection");
            collName += loopCollName + _realm;
          }
        }
      });
    } else {
      collName = collectionNameFromTableName(tableName) + _realm;

      if (docId.isNotEmpty) collName += "/" + docId;
    }

    print("@_docOrCollectionPath $tableName & docId $docId <=> $collName");
    return collName;
  }

  CollectionReference collectionRef (String name) {
        
    String collName = collectionNameFromTableName(name) + _realm;
    print("target collection => $collName");
    return _store.collection(collName);
  }  

  /// Write to or delete any document on firestore when you have the document reference.
  /// If data is not a serializable class, then it must be a map string dynamic. If it is NOT a serializable class, pass [isDataSerializable] as false.
  Future<void> updateDocWithRef (DocumentReference docRef, dynamic data, {bool doUpdate: true, bool isDataSerializable: true}) async {    

    Map<String, dynamic> dataMap = isDataSerializable ? data.toJson(): data;
    
    try {
      if (doUpdate) {  
        await docRef.update(dataMap);  
      } else {
        await docRef.delete();        
      }
    } catch (err) {
      print("error @updateDocument $err.");
    }
  }

  /// Write to any document on firestore when you have the document id OR are creating a new document.
  /// If data is not a serializable class, then it must be a map string dynamic. If it is NOT a serializable class, pass [isDataSerializable] as false.
  Future<bool> updateDocInCollection (String collName, dynamic data, {String docId:"", bool isDataSerializable: true}) async {
    
    Map<String, dynamic> dataMap = isDataSerializable ? data.toJson(): data;    
    CollectionReference collRef = collectionRef(collName);
    bool updated = false;
    try {
    // if (gHasConnectivity) {
      if (docId.isEmpty) {
        await collRef.doc().set(dataMap);
      } else {
        await collRef.doc(docId).update(dataMap);
      }
    // } else {
    //   usersCollRef?.doc(currentUserId).update(json);
    // }
    updated = true;
    } catch (err) {
      print("Error @updateDocInCollection: $err");
    }

    return updated;
  }

  /// Write to any document on firestore when you have a data map and the document id OR are creating a new document.
  Future<bool> updateDocInCollectionFromMap (String collName, Map<String, dynamic> dataMap, {String docId:""}) async {
    
    CollectionReference? collRef = collectionRef(collName);
    bool updated = false;

    try {
    // if (gHasConnectivity) {
      if (docId.isEmpty) {
        await collRef.doc().set(dataMap);
      } else {
        await collRef.doc(docId).update(dataMap);
      }
    // } else {
    //   usersCollRef?.doc(currentUserId).update(json);
    // }
    updated = true;
    } catch (err) {
      print("Error @updateDocInCollectionFromMap: $err");
    }

    return updated;
  }

  /// Write to or delete any document on firestore.
  /// If data is not a serializable class, then it must be a map string dynamic.
  /// If it is NOT a serializable class, pass [isDataSerializable] as false.
  Future<bool> touchDocument (String collName, {dynamic data, String docId: "", bool doWrite: true, bool isDataSerializable: true}) async {
    
    CollectionReference ref = collectionRef(collName);
    bool touched = false;

    if (!doWrite && docId.isEmpty) throw "Doc Id must be provided when deleting a document.";

    try {
      if (doWrite) {
        Map<String, dynamic> dataMap = isDataSerializable ? data.toJson() : data;
        
        // Todo: Let's have a timestamp on the server for the benefits outlined in firestore documentation.
        // json["Timestamp"] = FirebaseFirestore.in
        if (docId.isEmpty) {
          // if (gHasConnectivity) {
            await ref.add(dataMap);
          // } else {
          //   ref?.add(json);
          // }
        } else {
          // if (gHasConnectivity) {
            await ref.doc(docId).set(dataMap, SetOptions(merge: true));
          // } else {
          //   ref?.doc(docId).set(json, SetOptions(merge: true));
          // }
        }
      } else {
        // if (gHasConnectivity) {
          await ref.doc(docId).delete();
        // } else {
        //   ref?.doc(docId).delete();
        // }
      }
      touched = true;
    } catch (err) {
      print("error @touchDocumentInCollection $err.");      
    }

    return touched;
  }

  /// Read a collection by applying the query params (if any).
  /// Return a list of the documents or document references depending on arguments.
  /// Returns an empty list if no documents in the collection match the query.
  Future<List<dynamic>> readACollection(String tableName,
      {MyFirestoreQueryParam? queryParam, bool getDocSnapshots: false}) async {
    queryParam = queryParam ??= MyFirestoreQueryParam()..orderAsc = true;

    final collRef = collectionRef(tableName);// Oma fixed this line 22 Aug 2021.
    // Order by specified field or the first field in the first query criteria (if any).
    // Otherwise no ordering.
    // final bool descending = queryParam.orderAsc;

    Query useQuery = collRef;
    bool doNotRun = false;

    queryParam.where = queryParam.where;

    // If we have a query, we chain them in a loop.
    queryParam.where.forEach((param) {
      print(
          "reading ${collRef.id} collection... where field => ${param.fieldName}, => ${param.op}, value => ${param.value}");
      var value = param.value;

      // if (value == null) {
      //   doNotRun = true;
      //   print("null value => ${param.value}");
      // }

      switch (param.op) {
        case MyFirestoreFilterOp.isEqualTo:
          print("where case is equal to");
          useQuery = useQuery.where(param.fieldName, isEqualTo: value);
          break;
        case MyFirestoreFilterOp.isNotEqualTo:
          useQuery = useQuery.where(param.fieldName, isNotEqualTo: value);
          break;
        case MyFirestoreFilterOp.isLessThan:
          useQuery = useQuery.where(param.fieldName, isLessThan: value);
          break;
        case MyFirestoreFilterOp.isLessThanOrEqualTo:
          useQuery =
              useQuery.where(param.fieldName, isLessThanOrEqualTo: value);
          break;
        case MyFirestoreFilterOp.isGreaterThan:
          useQuery = useQuery.where(param.fieldName, isGreaterThan: value);
          break;
        case MyFirestoreFilterOp.isGreaterThanOrEqualTo:
          useQuery =
              useQuery.where(param.fieldName, isGreaterThanOrEqualTo: value);
          break;
        case MyFirestoreFilterOp.arrayContains:
          useQuery = useQuery.where(param.fieldName, arrayContains: value);

          break;
        case MyFirestoreFilterOp.arrayContainsAny:
          useQuery = useQuery.where(param.fieldName, arrayContainsAny: value);

          break;
        case MyFirestoreFilterOp.whereIn:
          useQuery = useQuery.where(param.fieldName, whereIn: value);

          break;
        case MyFirestoreFilterOp.whereNotIn:
          useQuery = useQuery.where(param.fieldName, whereNotIn: value);

          break;
        case MyFirestoreFilterOp.isNull:
          useQuery = useQuery.where(param.fieldName, isNull: value);
          break;
      }
    });

    try {
      // if (queryParam.orderBy) != null) {

      // useQuery = useQuery.orderBy(queryParam.orderBy, descending: descending);
      // } else if (queryParam.where.length > 0) {

      // useQuery = useQuery.orderBy(queryParam.where[0].fieldName, descending: descending);
      // }

      print("do not run $doNotRun");

      // if (doNotRun) {
      //   print("do not run query");
      //   return [];
      // }
      QuerySnapshot snapshot = await useQuery.get();

      print("read ${snapshot.docs.length} docs from collection ${collRef.id}");

      if (snapshot.docs.length > 0) {
        final list = getDocSnapshots ? snapshot.docs: snapshot.docs.map((doc) => doc.data()).toList();

        return list;
      } else {
        return [];
      }
    } catch (err) {
      print("error reading collection $tableName \n $err");

      return [];
    }
  }

  /// Return a single document snapshot for the passed collection and doc id.
  /// Returns null if no document bears that id.
  Future<dynamic> readADocumentById(String tableName, String docId, {bool getDocSnapshot: false}) async {
    // String collName = collectionNameFromTableName(tableName);
    DocumentSnapshot? snapshot = await collectionRef(tableName).doc(docId).get();

    if (snapshot.exists) {
      return getDocSnapshot ? snapshot : snapshot.data();
    } else {
      return null;
    }
  }

  /// Return a single document for the passed collection and query.
  Future<dynamic> readADocumentByQuery(String tableName, MyFirestoreQueryParam queryParam, {bool getDocSnapshot: false}) async {
    queryParam = queryParam;

    final listOfDocsOrSnapshots = await readACollection(tableName, queryParam: queryParam, getDocSnapshots: getDocSnapshot);
    
    if (listOfDocsOrSnapshots.length == 0) return null;

    return listOfDocsOrSnapshots[0];
  }

  Future<bool> batchWrite (List<MyBatchData> dataArray) async {
    final WriteBatch b = batch;
    print("writing ${dataArray.length} items in batch...");
    dataArray.forEach((data) {
      final String tableName = data.tableName;
      final String path = _docOrCollectionPath(tableName, docId: data.docId);
      final bool isEven = path.split("/").length % 2 == 0;
      final String docId = data.docId;
      late final DocumentReference ref;
      
      if (isEven) {
        ref = _store.doc(path);
      } else {
        ref = docId.isEmpty ? _store.collection(path).doc() : _store.collection(path).doc(docId);
      }

      switch (data.action.toLowerCase()) {
        case "update":
          b.update(ref, data.data);
          break;
        case "delete":
          b.delete(ref);
          break;
        case "insert":
        default:
          b.set(ref, data.data, data.setOptions);

          break;
      }
    });

    // Commit the batch
    try {
      await b.commit();

      return true;
    } catch (err) {
      print("error in batch commit $err");
      return false;
    }
  }
}

class MyFirestoreQueryParam {  
  MyFirestoreQueryParam();
  String orderBy = "";
  bool orderAsc = true;
  List<FirestoreWhereParam> where = [];
}

class FirestoreWhereParam {
  FirestoreWhereParam();
  String fieldName = "";
  MyFirestoreFilterOp op = MyFirestoreFilterOp.isEqualTo;
  dynamic value;
}

class MyBatchData {
  MyBatchData();

  String docId = "";
  String action = "insert";
  dynamic data = "";
  String tableName = "";
  SetOptions setOptions = SetOptions(merge: true);
}

enum MyFirestoreFilterOp {
  isEqualTo,
  isNotEqualTo,
  isLessThan,
  isLessThanOrEqualTo,
  isGreaterThan,
  isGreaterThanOrEqualTo,
  arrayContains,
  arrayContainsAny,
  whereIn,
  whereNotIn,
  isNull
}