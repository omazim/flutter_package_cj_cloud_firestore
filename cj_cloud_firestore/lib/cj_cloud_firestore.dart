library cj_cloud_firestore;

import 'dart:async';

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
  WriteBatch get batch => _store.batch();  

  String _collectionNameFromTableName (String tableName) {
        
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
          String loopCollName = _collectionNameFromTableName(v);

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
      collName = _collectionNameFromTableName(tableName) + _realm;

      if (docId.isNotEmpty) collName += "/" + docId;
    }

    print("@_docOrCollectionPath $tableName & docId $docId <=> $collName");
    return collName;
  }

  CollectionReference collectionRef (String name) {
        
    String collName = _collectionNameFromTableName(name) + _realm;
    print("target collection => $collName");
    return _store.collection(collName);
  }  

  /// Write to or delete any document on our firestore.
  Future<void> updateDocumentWithRef (DocumentReference docRef, dynamic data, {bool doUpdate: true, bool isDataSerializable: true}) async {    

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

  Future<bool> batchWrite(List<MyBatchData> dataArray) async {
    final WriteBatch b = batch;
    print("write ${dataArray.length} items in batch");
    dataArray.forEach((data) {
      final String tableName = data.tableName;
      final String path = _docOrCollectionPath(tableName, docId: data.docId);
      final bool isEven = path.split("/").length % 2 == 0;
      final String docId = data.docId;
      final DocumentReference ref =
          isEven ? _store.doc(path) : _store.collection(path).doc(docId);

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