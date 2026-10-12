part of 'generated.dart';

class CreateUserProfileVariablesBuilder {
  String username;
  String email;

  final FirebaseDataConnect _dataConnect;
  CreateUserProfileVariablesBuilder(this._dataConnect, {required  this.username,required  this.email,});
  Deserializer<CreateUserProfileData> dataDeserializer = (dynamic json)  => CreateUserProfileData.fromJson(jsonDecode(json));
  Serializer<CreateUserProfileVariables> varsSerializer = (CreateUserProfileVariables vars) => jsonEncode(vars.toJson());
  Future<OperationResult<CreateUserProfileData, CreateUserProfileVariables>> execute() {
    return ref().execute();
  }

  MutationRef<CreateUserProfileData, CreateUserProfileVariables> ref() {
    CreateUserProfileVariables vars= CreateUserProfileVariables(username: username,email: email,);
    return _dataConnect.mutation("CreateUserProfile", dataDeserializer, varsSerializer, vars);
  }
}

@immutable
class CreateUserProfileUserUpsert {
  final String id;
  CreateUserProfileUserUpsert.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateUserProfileUserUpsert otherTyped = other as CreateUserProfileUserUpsert;
    return id == otherTyped.id;
    
  }
  @override
  int get hashCode => id.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    return json;
  }

  CreateUserProfileUserUpsert({
    required this.id,
  });
}

@immutable
class CreateUserProfileData {
  final CreateUserProfileUserUpsert user_upsert;
  CreateUserProfileData.fromJson(dynamic json):
  
  user_upsert = CreateUserProfileUserUpsert.fromJson(json['user_upsert']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateUserProfileData otherTyped = other as CreateUserProfileData;
    return user_upsert == otherTyped.user_upsert;
    
  }
  @override
  int get hashCode => user_upsert.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['user_upsert'] = user_upsert.toJson();
    return json;
  }

  CreateUserProfileData({
    required this.user_upsert,
  });
}

@immutable
class CreateUserProfileVariables {
  final String username;
  final String email;
  @Deprecated('fromJson is deprecated for Variable classes as they are no longer required for deserialization.')
  CreateUserProfileVariables.fromJson(Map<String, dynamic> json):
  
  username = nativeFromJson<String>(json['username']),
  email = nativeFromJson<String>(json['email']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final CreateUserProfileVariables otherTyped = other as CreateUserProfileVariables;
    return username == otherTyped.username && 
    email == otherTyped.email;
    
  }
  @override
  int get hashCode => Object.hashAll([username.hashCode, email.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['username'] = nativeToJson<String>(username);
    json['email'] = nativeToJson<String>(email);
    return json;
  }

  CreateUserProfileVariables({
    required this.username,
    required this.email,
  });
}

