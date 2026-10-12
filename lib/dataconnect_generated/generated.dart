library dataconnect_generated;
import 'package:firebase_data_connect/firebase_data_connect.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

part 'create_user_profile.dart';

part 'get_my_profile.dart';







class ExampleConnector {
  
  
  CreateUserProfileVariablesBuilder createUserProfile ({required String username, required String email, }) {
    return CreateUserProfileVariablesBuilder(dataConnect, username: username,email: email,);
  }
  
  
  GetMyProfileVariablesBuilder getMyProfile () {
    return GetMyProfileVariablesBuilder(dataConnect, );
  }
  

  static ConnectorConfig connectorConfig = ConnectorConfig(
    'us-east4',
    'example',
    'wolvesclub',
  );

  ExampleConnector({required this.dataConnect});
  static ExampleConnector get instance {
    
    CacheSettings cacheSettings = CacheSettings(
      maxAge: Duration(milliseconds:0),
      storage: CacheStorage.persistent,
    );
    
    return ExampleConnector(
        dataConnect: FirebaseDataConnect.instanceFor(
            connectorConfig: connectorConfig,
            
            cacheSettings: cacheSettings,
            
            sdkType: CallerSDKType.generated));
  }

  FirebaseDataConnect dataConnect;
}
