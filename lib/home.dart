import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_wrapper/connectivity_wrapper.dart';
import 'package:device_information/device_information.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:timer_pic/utils/snack.dart';
import 'package:uuid/uuid.dart';


class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final Battery _battery = Battery();
  BatteryState? _batteryState;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  String _platformVersion = 'Unknown',
      _imeiNo = "";
  String _locationMessage = "";
  final String _formattedDate = DateFormat('yyyy-MM-dd – kk:mm:ss').format(DateTime.now());
  late CameraController _controller;
   Future<void>? _initializeControllerFuture;
  late List<CameraDescription> _cameras;
  late CameraDescription _selectedCamera;
  int _start = 900;
  Timer? _timer;
  String _timerText = '';
  XFile? _file;
  late String _itemId;
  final Connectivity _connectivity = Connectivity();
  File? _localFile;


  initPlatformState() async{
    late String platformVersion,
        imeiNo = '';
    // Platform messages may fail,
    // so we use a try/catch PlatformException.
    try {
      platformVersion = await DeviceInformation.platformVersion;
      imeiNo = await DeviceInformation.deviceIMEINumber;
    } on PlatformException catch (e) {
      platformVersion = '${e.message}';
      print('the error issssssssssssss $platformVersion');
    }
    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;
    setState(() {
      _platformVersion = platformVersion;
      _imeiNo = imeiNo;
    });
  }
  void _updateBatteryState(BatteryState state) {
    if (_batteryState == state) return;
    setState(() {
      _batteryState = state;
    });
  }

  void _getCurrentLocation() async {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    print(position.latitude);
    print(position.longitude);

    setState(() {
      _locationMessage = "Latitude: ${position.latitude} Longitude: ${position.longitude}";
    });
  }
  void _requestLocationPermission() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      return;
    } else if (status.isDenied) {
      return;
    } else if (status.isPermanentlyDenied) {
      return;
    }
  }

  Future<String?> _uploadItemImageToStorage(XFile image) async {
    if (image != null) {
      if(await _connectivity.checkConnectivity() == ConnectivityResult.none) {
        // No internet connection, save the image locally
        final directory = await getApplicationDocumentsDirectory();
         _localFile = File('${directory.path}/image.jpg');
        final bytes = await image.readAsBytes();
        await _localFile?.writeAsBytes(bytes);
        snack(context, 'upload saved locally due to no internet connection. Connect to internet to continue');
        return _localFile?.path;
      } else {
        final ref = FirebaseStorage.instance.ref().child('singleImages/${DateTime.now().millisecondsSinceEpoch}.jpg');
        final task = ref.putFile(File(image.path));
        final snapshot = await task.whenComplete(() => null);
        String downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      }
    }
    return null;
  }

  _uploadLocalImageToStorage(File image)async{
    if (image != null) {
      final ref = FirebaseStorage.instance.ref().child('singleImages/${DateTime.now().millisecondsSinceEpoch}.jpg');
      final task = ref.putFile(image);
      final snapshot = await task.whenComplete(() => null);
      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    }
    return null;
  }

  _uploadImageToFirestore()async{
    EasyLoading.show(status: 'Please wait');
    if(_file != null){
     try{
       String? _image = await _uploadItemImageToStorage(_file!);
       _itemId = Uuid().v4();
       if(await _connectivity.checkConnectivity() == ConnectivityResult.none){
         EasyLoading.dismiss();
       }else{
         await FirebaseFirestore.instance.collection('Images').doc(_itemId).set({
           'Image': _image
         });
         EasyLoading.dismiss();
         return snack(context, 'Upload Complete');
       }
     }catch(e){
       print('the errorsssss areeeeeee ${e.toString()}');
       EasyLoading.dismiss();
     }
    }
  }
  Future<void> uploadLocalImage() async {
    if(_localFile != null){

      if(await _connectivity.checkConnectivity() == ConnectivityResult.none){
        ;
        return;
      }else{

        EasyLoading.show();
        final downloadUrl = await _uploadLocalImageToStorage(_localFile!);

        await FirebaseFirestore.instance.collection('LocalImages').doc(_itemId).set({
          'Image': downloadUrl
        }).whenComplete(()async{
          await _localFile!.delete();
        });
        EasyLoading.dismiss();
        return snack(context, 'Local image successfully uploaded');
      }
    }

  }

  void startTimer() async{
    const oneSec = Duration(seconds: 1);
    _timer = Timer.periodic(
      oneSec,
          (Timer timer) async{
        if (_start == 0) {
          setState((){
            restartTimer();
          });
          try {
            await _initializeControllerFuture;

            _file = await _controller.takePicture();
            _uploadImageToFirestore();
          } catch (e) {
            print(e);
          }
        } else {
          int minutes = _start ~/ 60;
          int seconds = _start % 60;
          String formattedTime =
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
          setState(() {
            _timerText = formattedTime;
            _start--;
          });
        }
      },
    );
  }
  void restartTimer() {
    if (_timer != null) {
      _timer!.cancel();
    }
    setState(() {
      _start = 900;
    });
    startTimer();
  }


  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    initPlatformState();
    startTimer();
    _requestLocationPermission();
    _getCurrentLocation();
    uploadLocalImage();
    _battery.batteryState.then(_updateBatteryState);
    _batteryStateSubscription =
        _battery.onBatteryStateChanged.listen(_updateBatteryState);

    // Get the first available camera
    availableCameras().then((value){
      setState(() {
        _cameras = value;
        _selectedCamera = _cameras[0];
      });
      // Initialize the camera controller with the first available camera
      _controller = CameraController(
        _selectedCamera,
        ResolutionPreset.high,
      );

      // Initialize the camera controller
      _initializeControllerFuture = _controller.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     body: Padding(
       padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12),
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Container(
             height: MediaQuery.of(context).size.height*0.5,
             width: MediaQuery.of(context).size.width,
             decoration: _file != null ?BoxDecoration(
                 color: Colors.blue,
                 borderRadius: BorderRadius.circular(20),
                 image: DecorationImage(
                     image: FileImage(
                         File(_file!.path)),
                   fit: BoxFit.cover
                 )
             ):
             BoxDecoration(
               color: Colors.grey.shade300,
               borderRadius: BorderRadius.circular(20),
             )
             ,
           ),
           Row(
             children: [
               const Text('Imei of this device is: ',
                 style: TextStyle(
                     fontSize: 16,
                     fontWeight: FontWeight.w600,
                 ),
               ),
               _imeiNo != '' ?Text(_imeiNo,
                 style: const TextStyle(
                     fontSize: 16,
                     fontWeight: FontWeight.w600,
                 ),
               ):
               Text(_platformVersion,
                 style: const TextStyle(
                     fontSize: 16,
                     fontWeight: FontWeight.w600,
                 ),
               ),
             ],
           ),
            const SizedBox(
              height: 10,
            ),
            ConnectivityWidgetWrapper(
             stacked: false,
               offlineWidget: Row(
                 children: const [
                   Text('Connection Statue: ',
                     style: TextStyle(
                         fontWeight: FontWeight.w600,
                         fontSize: 16,
                     ),
                   ),
                   Text('Offline',
                     style: TextStyle(
                         color: Colors.red,
                         fontWeight: FontWeight.w600,
                         fontSize: 16
                     ),
                   ),
                 ],
               ),
               child: Row(
                 children: const [
                   Text('Connection Statue: ',
                     style: TextStyle(
                         fontWeight: FontWeight.w600,
                         fontSize: 16,
                     ),
                   ),
                   Text('Online',
                     style: TextStyle(
                         color: Colors.green,
                         fontWeight: FontWeight.w600,
                         fontSize: 16
                     ),
                   ),
                 ],
               ),
           ),
           const SizedBox(
             height: 10,
           ),
           Row(
             children: [
               const Text('Battery State: ',
                 style: TextStyle(
                     fontWeight: FontWeight.w600,
                     fontSize: 16,
                 ),
               ),
               Text('$_batteryState',
                 style: const TextStyle(
                     color: Colors.green,
                     fontWeight: FontWeight.w600,
                     fontSize: 16
                 ),
               ),
             ],
           ),
           const SizedBox(
             height: 10,
           ),
           SizedBox(
             height: 20,
             child: ElevatedButton(
               style: ButtonStyle(
                 backgroundColor: MaterialStateProperty.resolveWith<Color>(
                       (Set<MaterialState> states) {
                     if (states.contains(MaterialState.pressed)) {
                       return Colors.grey.shade300; // Color when the button is pressed
                     }
                     return Colors.black; // Default color
                   },
                 ),
               ),
               onPressed: () {
                 _battery.batteryLevel.then(
                       (batteryLevel) {
                     showDialog<void>(
                       context: context,
                       builder: (_) => AlertDialog(
                         content: Text('Battery: $batteryLevel%'),
                         actions: <Widget>[
                           TextButton(
                             onPressed: () {
                               Navigator.pop(context);
                             },
                             child: const Text('OK'),
                           )
                         ],
                       ),
                     );
                   },
                 );
               },
               child: const Text('Get battery level'),
             ),
           ),
           const SizedBox(
             height: 10,
           ),
           Row(
             children: [

                    const Text('location: ',
                     style: TextStyle(
                       fontWeight: FontWeight.w600,
                       fontSize: 16,
                     ),
                   ),

               Text(_locationMessage,
                 style: const TextStyle(
                     fontWeight: FontWeight.w600,
                     fontSize: 16,
                 ),
               )
             ],
           ),
           const SizedBox(
             height: 10,
           ),
           Text(_formattedDate),
           const SizedBox(
             height: 10,
           ),
           FutureBuilder<void>(
             future: _initializeControllerFuture,
             builder: (context, snapshot) {
               if (snapshot.connectionState == ConnectionState.done) {
                 // If the camera controller has been initialized, show the camera preview
                 return  CircleAvatar(
                   radius: 50,
                   backgroundColor: Colors.white,
                   child: Text(_timerText.toString(),
                     style: const TextStyle(
                       fontSize: 22,
                       fontWeight: FontWeight.w800,
                       color: Colors.black
                     ),
                   ),
                 );
               } else {
                 // Otherwise, show a loading indicator
                 return Center(child: CircularProgressIndicator());
               }
             },
           ),
           const SizedBox(
             height: 30,
           ),
           _localFile != null && _localFile!.existsSync()?ConnectivityWidgetWrapper(
            stacked: false,
              offlineWidget:  ElevatedButton(
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith<Color>(
                          (Set<MaterialState> states) {
                        if (states.contains(MaterialState.pressed)) {
                          return Colors.red; // Color when the button is pressed
                        }
                        return Colors.red; // Default color
                      },
                    ),
                  ),
                  onPressed: (){
                  }, child: const Text('No Network')
              ),
              child: ElevatedButton(
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith<Color>(
                          (Set<MaterialState> states) {
                        if (states.contains(MaterialState.pressed)) {
                          return Colors.green; // Color when the button is pressed
                        }
                        return Colors.green; // Default color
                      },
                    ),
                  ),
                  onPressed: (){

                    uploadLocalImage();
                  }, child: const Text('upload local image')
              ),
          ): Container()
         ],
       ),
     ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        onPressed: () async {
          // Take a picture
          try {
            await _initializeControllerFuture;

             _file = await _controller.takePicture();
             _uploadImageToFirestore();
          } catch (e) {
            print(e);
          }
        },
        child: const Icon(Icons.camera_alt, color: Colors.white,),
      ),
    );
  }
  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
    if (_batteryStateSubscription != null) {
      _batteryStateSubscription!.cancel();
    }
  }
}
