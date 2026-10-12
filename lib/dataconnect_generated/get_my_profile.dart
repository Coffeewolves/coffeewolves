part of 'generated.dart';

class GetMyProfileVariablesBuilder {
  
  final FirebaseDataConnect _dataConnect;
  GetMyProfileVariablesBuilder(this._dataConnect, );
  Deserializer<GetMyProfileData> dataDeserializer = (dynamic json)  => GetMyProfileData.fromJson(jsonDecode(json));
  
  Future<QueryResult<GetMyProfileData, void>> execute({QueryFetchPolicy fetchPolicy = QueryFetchPolicy.preferCache}) {
    return ref().execute(fetchPolicy: fetchPolicy);
  }

  QueryRef<GetMyProfileData, void> ref() {
    
    return _dataConnect.query("GetMyProfile", dataDeserializer, emptySerializer, null);
  }
}

@immutable
class GetMyProfileUser {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final double giftCardBalance;
  GetMyProfileUser.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  username = nativeFromJson<String>(json['username']),
  email = nativeFromJson<String>(json['email']),
  avatarUrl = json['avatarUrl'] == null ? null : nativeFromJson<String>(json['avatarUrl']),
  giftCardBalance = nativeFromJson<double>(json['giftCardBalance']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetMyProfileUser otherTyped = other as GetMyProfileUser;
    return id == otherTyped.id && 
    username == otherTyped.username && 
    email == otherTyped.email && 
    avatarUrl == otherTyped.avatarUrl && 
    giftCardBalance == otherTyped.giftCardBalance;
    
  }
  @override
  int get hashCode => Object.hashAll([id.hashCode, username.hashCode, email.hashCode, avatarUrl.hashCode, giftCardBalance.hashCode]);
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['username'] = nativeToJson<String>(username);
    json['email'] = nativeToJson<String>(email);
    if (avatarUrl != null) {
      json['avatarUrl'] = nativeToJson<String?>(avatarUrl);
    }
    json['giftCardBalance'] = nativeToJson<double>(giftCardBalance);
    return json;
  }

  GetMyProfileUser({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    required this.giftCardBalance,
  });
}

@immutable
class GetMyProfileData {
  final GetMyProfileUser? user;
  GetMyProfileData.fromJson(dynamic json):
  
  user = json['user'] == null ? null : GetMyProfileUser.fromJson(json['user']);
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) {
      return true;
    }
    if(other.runtimeType != runtimeType) {
      return false;
    }

    final GetMyProfileData otherTyped = other as GetMyProfileData;
    return user == otherTyped.user;
    
  }
  @override
  int get hashCode => user.hashCode;
  

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    if (user != null) {
      json['user'] = user!.toJson();
    }
    return json;
  }

  GetMyProfileData({
    this.user,
  });
}

