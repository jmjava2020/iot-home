/*
 * Package : iot_home_sensors
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 29/09/2017
 * Copyright :  S.Hamblett
 */

part of iot_home_sensors;

/// The interface class to Googles's Iot-Core MQTT bridge
class MqttBridge {
  /// Construction
  MqttBridge(this.deviceId);

  /// Device Id
  String deviceId;

  /// The MQTT client
  mqtt.MqttClient client;

  /// The Iot-Core server and port, we use 443
  final String server = 'mqtt.googleapis.com';
  final int port = 443;

  /// Logging
  bool logging = false;

  /// Token signers
  Map<String, jwt.TokenSigner> signers = new Map<String, jwt.TokenSigner>();

  /// JWT encoder
  jwt.Encoder encoder;

  /// Password- encoded and signed JWYT
  String password;

  /// Are we initialised
  bool initialised = false;

  /// Initialise and connect to the Mqtt bridge
  void initialise() {
    // Initialize the token signers, in our case just RS256
    final String sensorPkFilename = deviceId + "-pk.key";
    final String pkPath =
        path.join(path.current, "lib", "src", "secret", sensorPkFilename);
    final File pkFile = new File(pkPath);
    final String pk = pkFile.readAsStringSync();
    signers['RS256'] = jwt.toTokenSigner(jwt.createRS256Signer(pk));
    encoder = new jwt.Encoder(jwt.composeTokenSigners(signers));
    getJWT().then((String enc) {
      password = enc;
      client = new mqtt.MqttClient(server, getClientId());
      client.port = port;
      client.secure = true;
      final String username = "unused";
      client.setProtocolV311();
      client.logging(on: logging);
      client.connect(username, password).then((dynamic f) {
        if (client.connectionStatus.state ==
            mqtt.MqttConnectionState.connected) {
          print("SUCCESS - the MQTT bridge is connected");
          initialised = true;
        } else {
          print(
              "ERROR - the MQTT bridge is not connected - try again with logging on");
        }
      });
    });
  }

  /// Update an integer value
  void update(SensorData data) {
    final typed.Uint8Buffer buff = _sensorDataBuffer(data);
    client.publishMessage(getTelemetryTopic(), mqtt.MqttQos.atMostOnce, buff);
  }

  /// Get the client id for the sensor
  String getClientId() {
    return "projects/" +
        Secrets.projectId +
        "/locations/" +
        Secrets.region +
        "/registries/" +
        Secrets.registry +
        "/devices/" +
        deviceId;
  }

  /// Get the telemetry topic
  String getTelemetryTopic() {
    return "/devices/" + deviceId + "/events";
  }

  /// Get the JWT token
  Future<String> getJWT() async {
    final int iat =
        ((new DateTime.now().millisecondsSinceEpoch) / 1000).round();
    final int exp = ((new DateTime.now()
                .add(new Duration(hours: 24))
                .millisecondsSinceEpoch) /
            1000)
        .round();
    final jwt.Jwt token =
        new jwt.Jwt.RS256({'iat': iat, 'exp': exp, 'aud': Secrets.projectId});
    final jwt.EncodedJwt enc = await encoder.convert(token);
    return enc.toString();
  }

  typed.Uint8Buffer _sensorDataBuffer(SensorData data) {
    return new typed.Uint8Buffer()..addAll(data.toString().codeUnits.toList());
  }
}
