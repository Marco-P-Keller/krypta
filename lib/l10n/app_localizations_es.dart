// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'Krypta ECC';

  @override
  String get calculator => 'Calculadora';

  @override
  String get messenger => 'Mensajería';

  @override
  String get settings => 'Ajustes';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contactos';

  @override
  String get setupTitle => 'Bienvenido a Krypta ECC';

  @override
  String get setupSubtitle => 'Configura tus códigos secretos para empezar';

  @override
  String get secretCodeLabel => 'Código secreto';

  @override
  String get secretCodeHint =>
      'Introduce el código que desbloquea tu mensajería';

  @override
  String get decoyCodeLabel => 'Código señuelo';

  @override
  String get decoyCodeHint =>
      'Introduce un código que abre una mensajería falsa';

  @override
  String get deleteCodeLabel => 'Código de borrado';

  @override
  String get deleteCodeHint =>
      'Introduce un código que borra todos los datos al instante';

  @override
  String get setupComplete => 'Configuración completada';

  @override
  String get setupContinue => 'Continuar';

  @override
  String get setupCodesInfo =>
      'Todos los códigos deben ser distintos y tener al menos 4 dígitos';

  @override
  String get back => 'Atrás';

  @override
  String get next => 'Siguiente';

  @override
  String get newChat => 'Nuevo chat';

  @override
  String get typeMessage => 'Escribe un mensaje...';

  @override
  String get send => 'Enviar';

  @override
  String get delivered => 'Entregado';

  @override
  String get sent => 'Enviado';

  @override
  String get read => 'Leído';

  @override
  String get typing => 'escribiendo...';

  @override
  String get selfDestructTimer => 'Temporizador de autodestrucción';

  @override
  String get seconds30 => '30 segundos';

  @override
  String get minutes5 => '5 minutos';

  @override
  String get hour1 => '1 hora';

  @override
  String get day1 => '1 día';

  @override
  String get week1 => '1 semana';

  @override
  String get off => 'Desactivado';

  @override
  String get emergencyDelete => 'Borrado de emergencia';

  @override
  String get emergencyDeleteDescription =>
      'Borra de inmediato todos los datos y claves, y cierra la sesión';

  @override
  String get allDataDeleted => 'Se han borrado todos los datos';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get securitySettings => 'Seguridad';

  @override
  String get changeSecretCode => 'Cambiar el código secreto';

  @override
  String get changeDecoyCode => 'Cambiar el código señuelo';

  @override
  String get changeDeleteCode => 'Cambiar el código de borrado';

  @override
  String get biometricUnlock => 'Desbloqueo biométrico';

  @override
  String get biometricDescription =>
      'Exigir Face ID o huella tras introducir el código';

  @override
  String get autoDeleteMessages => 'Borrado automático de mensajes';

  @override
  String get accountSection => 'Cuenta';

  @override
  String get privacySection => 'Privacidad';

  @override
  String get dangerZone => 'Zona de riesgo';

  @override
  String get deleteAccount => 'Borrar cuenta y datos';

  @override
  String get about => 'Acerca de Krypta ECC';

  @override
  String version(String version) {
    return 'Versión $version';
  }

  @override
  String get noChats => 'Aún no hay conversaciones';

  @override
  String get noChatsSubtitle =>
      'Inicia un chat nuevo para empezar a escribir de forma segura';

  @override
  String get decoyTitle => 'Mensajes';

  @override
  String get encryptionInfo =>
      'Los mensajes están cifrados de extremo a extremo';

  @override
  String get anonymousUser => 'Usuario anónimo';

  @override
  String get userIdLabel => 'Tu ID';

  @override
  String get userIdCopied => 'ID de usuario copiado al portapapeles';

  @override
  String get addContactById => 'Añadir contacto por ID';

  @override
  String get contactIdHint => 'Introduce el ID del contacto';

  @override
  String get addContact => 'Añadir contacto';

  @override
  String get cannotAddYourself => 'No puedes añadirte a ti mismo';

  @override
  String get userNotFound => 'Usuario no encontrado';

  @override
  String get myQrCode => 'Mi código QR';

  @override
  String get scanQrCode => 'Escanear código QR';

  @override
  String get scanQr => 'Escanear QR';

  @override
  String get qrScanHint => 'Apunta la cámara a un código QR de Krypta';

  @override
  String get qrShareHint => 'Deja que otros lo escaneen para conectarse';

  @override
  String get yourQrCode => 'Tu código QR';

  @override
  String get idCopied => 'ID copiado';

  @override
  String get qrWebUnavailable =>
      'El escaneo de códigos QR no está disponible en la web.\nUsa un dispositivo móvil para escanear códigos QR.';

  @override
  String get thatsYourOwnId => 'Ese es tu propio ID';

  @override
  String get renameChat => 'Renombrar chat';

  @override
  String get chatName => 'Nombre del chat';

  @override
  String get save => 'Guardar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get skip => 'Omitir';

  @override
  String get deleteChat => 'Borrar chat';

  @override
  String get clearChat => 'Vaciar chat';

  @override
  String clearChatConfirm(String name) {
    return '¿Eliminar todos los mensajes de este chat? En el dispositivo de $name también desaparecerán los mensajes que enviaste; los suyos se mantienen. Esto no se puede deshacer.';
  }

  @override
  String get autoDeleteTimer => 'Temporizador de borrado automático';

  @override
  String get autoDeleteHint =>
      'Los mensajes nuevos de este chat se autodestruirán tras el tiempo seleccionado.';

  @override
  String get chatDefault => 'Valor por defecto del chat';

  @override
  String chatDefaultWithTimer(String timer) {
    return 'Valor por defecto del chat ($timer)';
  }

  @override
  String messagesAutoDelete(String timer) {
    return 'Los mensajes se borran automáticamente tras $timer';
  }

  @override
  String get onlyVisibleToYou => 'Solo visible para ti';

  @override
  String get burnAfterRead => 'Destruir tras leer';

  @override
  String get passwordProtected => 'Protegido con contraseña';

  @override
  String get lockMessage => 'Bloquear mensaje';

  @override
  String get lockMessageHint =>
      'Establece una contraseña para el siguiente mensaje. El destinatario deberá introducirla para leerlo.';

  @override
  String get enterPassword => 'Introduce la contraseña';

  @override
  String get setPassword => 'Establecer contraseña';

  @override
  String get passwordRequired => 'Se requiere contraseña';

  @override
  String get passwordRequiredHint =>
      'Introduce la contraseña para descifrar este mensaje.';

  @override
  String get password => 'Contraseña';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get unlocked => 'Desbloqueado';

  @override
  String get wrongPassword => 'Contraseña incorrecta';

  @override
  String get tapToUnlock => 'Toca para desbloquear';

  @override
  String get nameThisContact => 'Ponle nombre a este contacto';

  @override
  String get nameContactHint =>
      'Dale un nombre a este contacto para saber quién es. Solo tú puedes ver esta etiqueta.';

  @override
  String get nameContactPlaceholder => 'p. ej. Alex, mamá, trabajo...';

  @override
  String get selfDestructTimerLabel => 'Temporizador de autodestrucción';

  @override
  String get vaultPassword => 'Contraseña de la bóveda';

  @override
  String get vaultPasswordDescription =>
      'Exigir una contraseña segura tras el código, antes de acceder a la mensajería';

  @override
  String get vaultPasswordTitle => 'Bóveda bloqueada';

  @override
  String get vaultPasswordHint =>
      'Introduce la contraseña de la bóveda para acceder a la mensajería.';

  @override
  String get setVaultPassword => 'Establecer contraseña de la bóveda';

  @override
  String get changeVaultPassword => 'Cambiar la contraseña de la bóveda';

  @override
  String get removeVaultPassword => 'Quitar la contraseña de la bóveda';

  @override
  String get vaultPasswordSet => 'Contraseña de la bóveda establecida';

  @override
  String get vaultPasswordRemoved => 'Contraseña de la bóveda eliminada';

  @override
  String get vaultPasswordRules =>
      'Al menos 10 caracteres, con mayúscula, minúscula, número y carácter especial.';

  @override
  String get newPassword => 'Nueva contraseña';

  @override
  String get confirmPassword => 'Confirmar contraseña';

  @override
  String get passwordsDoNotMatch => 'Las contraseñas no coinciden';

  @override
  String get passwordTooWeak => 'La contraseña no cumple los requisitos';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado';

  @override
  String get delete => 'Borrar';

  @override
  String get deleteMessage => 'Borrar mensaje';

  @override
  String get deleteMessageConfirm =>
      'Este mensaje se borrará definitivamente de este dispositivo.';

  @override
  String get deleteForMe => 'Borrar para mí';

  @override
  String get deleteForEveryone => 'Borrar para todos';

  @override
  String get deleteForEveryoneConfirm =>
      'Este mensaje se borrará tanto para ti como para el destinatario.';

  @override
  String get qrInvalidFormat =>
      'Formato de código QR no válido. Solo se aceptan códigos QR de Krypta.';

  @override
  String get qrUnsupportedVersion =>
      'Versión de código QR no compatible. Actualiza la aplicación.';

  @override
  String get qrFingerprintMismatch =>
      'Aviso de seguridad: la huella del código QR ha sido manipulada. Operación cancelada.';

  @override
  String get qrKeyMismatch =>
      'AVISO DE SEGURIDAD: la clave del servidor NO coincide con la del código QR. Posible ataque detectado. El contacto ha sido bloqueado.';

  @override
  String get qrVerified => 'Clave verificada';

  @override
  String get verificationStale => 'La verificación tiene más de 90 días';

  @override
  String get verifyNow => 'Volver a verificar';

  @override
  String get showTutorial => 'Ver el tutorial otra vez';

  @override
  String get showTutorialSubtitle => 'Repetir la introducción';

  @override
  String get openSourceLicenses => 'Licencias de código abierto';

  @override
  String get openSourceLicensesSubtitle => 'Bibliotecas de terceros y avisos';

  @override
  String get aboutClose => 'Cerrar';

  @override
  String get confirm => 'Confirmar';

  @override
  String lockedForSeconds(int seconds) {
    return 'Bloqueado durante $seconds segundos.';
  }

  @override
  String wrongPasswordWarning(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Quedan $remaining intentos',
      one: 'Queda 1 intento',
    );
    return 'Contraseña incorrecta. $_temp0 antes de que se borren todos los datos.';
  }

  @override
  String get keysNotPublishedDenied =>
      'El servidor ha rechazado tus claves: nadie puede escribirte.';

  @override
  String get keysNotPublishedFailed =>
      'No se han podido publicar tus claves: nadie puede escribirte.';

  @override
  String get biometricUnlockReason => 'Desbloquear Krypta Messenger';

  @override
  String get deviceCompromised => 'El dispositivo podría estar comprometido.';

  @override
  String get deviceCompromisedDegraded =>
      'El dispositivo podría estar comprometido. Seguridad por hardware desactivada.';

  @override
  String get fieldRequired => 'Obligatorio';

  @override
  String codeMinDigits(int count) {
    return 'Al menos $count dígitos';
  }

  @override
  String get codeDigitsOnly => 'Solo dígitos';

  @override
  String get deleteCodeMustDiffer =>
      'El código de borrado debe ser distinto de tu código secreto.';

  @override
  String get setupFailed => 'La configuración ha fallado. Inténtalo de nuevo.';

  @override
  String get setupSecretCodeSubtitle =>
      'Introdúcelo en la calculadora para abrir tu bóveda.';

  @override
  String get setupDeleteCodeSubtitle =>
      'Borra todo al instante. Úsalo solo en emergencias.';

  @override
  String get contactKeyChangedWarning =>
      'La clave de seguridad de este contacto ha cambiado. Los mensajes están bloqueados hasta que verifiques su identidad. Escanea su código QR o comparad los números de seguridad para seguir escribiendo.';

  @override
  String get verifyIdentity => 'Verificar identidad';

  @override
  String get safetyNumberCompareHint =>
      'Comparad los números de seguridad o escanead los códigos QR para verificar el cifrado de extremo a extremo.';

  @override
  String get viewSafetyNumber => 'Ver número de seguridad';

  @override
  String get safetyNumberTitle => 'Número de seguridad';

  @override
  String get safetyNumberCopied => 'Número de seguridad copiado';

  @override
  String get safetyNumberMatchHint =>
      'Compara este número con tu contacto. Si coinciden, vuestra conversación es segura.';

  @override
  String get verificationFailedKeyMismatch =>
      'La verificación ha fallado: las claves no coinciden';

  @override
  String get markVerified => 'Marcar como verificado';

  @override
  String get securitySettingsReason => 'Cambiar los ajustes de seguridad';

  @override
  String get vaultPasswordReAuthHint =>
      'Introduce la contraseña de la bóveda para cambiar los ajustes de seguridad.';

  @override
  String get codeAlreadyInUse => 'Este código ya se usa para otra acción.';

  @override
  String get deviceSecure => 'Dispositivo seguro';

  @override
  String get deviceCompromisedDetected => 'Compromiso detectado';

  @override
  String get deviceStatusUnknown => 'Estado desconocido';

  @override
  String get deviceSecureSubtitle => 'Sin indicios de root, jailbreak ni Frida';

  @override
  String get deviceCompromisedSubtitle =>
      'Se ha detectado root, jailbreak o instrumentación. Seguridad por hardware desactivada.';

  @override
  String get deviceStatusUnknownSubtitle =>
      'La comprobación de integridad ha fallado: modo restringido activo.';

  @override
  String get hardwareEnclave => 'Enclave de hardware';

  @override
  String get hardwareTee => 'Almacén de claves TEE';

  @override
  String get hardwareSoftware => 'Almacén de claves por software';

  @override
  String get hardwareBoundSubtitle =>
      'Clave de la base de datos vinculada al hardware';

  @override
  String get hardwareEnclaveSubtitle => 'StrongBox/Secure Enclave disponible';

  @override
  String get hardwareTeeSubtitle =>
      'Clave guardada en el Trusted Execution Environment';

  @override
  String get hardwareSoftwareSubtitle =>
      'No hay seguridad por hardware disponible';

  @override
  String get pushPrivacy => 'Privacidad de las notificaciones';

  @override
  String get pushPrivacyOn => 'Activada: los mensajes se recuperan por sondeo';

  @override
  String get pushPrivacyOff => 'Desactivada: notificaciones push activas';

  @override
  String get readReceipts => 'Confirmaciones de lectura';

  @override
  String get readReceiptsOn => 'Activadas: el remitente ve cuándo lees';

  @override
  String get readReceiptsOff => 'Desactivadas: máxima privacidad';

  @override
  String get deliveryReceipts => 'Confirmaciones de entrega';

  @override
  String get deliveryReceiptsOn =>
      'Activadas: el remitente ve cuándo se entrega';

  @override
  String get deliveryReceiptsOff => 'Desactivadas: máxima privacidad';

  @override
  String get privacyPolicyBody =>
      'Krypta ECC — Política de privacidad\n\nÚltima actualización: abril de 2026\n\n1. Responsable\nConnexa GmbH\nContacto: https://connexa-gmbh.ch\n\n2. ¿Qué datos se recogen?\nKrypta recoge tan pocos datos como es técnicamente posible:\n• ID anónimo de Firebase (sin correo, sin nombre, sin número de teléfono)\n• Clave pública de cifrado (X25519)\n• Token push de FCM (para las notificaciones)\n\n3. Cifrado\nTodos los mensajes están cifrados de extremo a extremo (protocolo Signal: X3DH + Double Ratchet). En ningún momento tiene el servidor acceso al texto en claro de tus mensajes. Cifrado: XChaCha20-Poly1305. Hash de contraseñas: Argon2id.\n\n4. Almacenamiento de datos\n• Los mensajes se guardan únicamente en tu dispositivo (cifrados)\n• El servidor actúa solo como relé temporal: los mensajes se borran tras la entrega\n• Las claves se guardan en el Llavero de iOS / Android Keystore\n\n5. Sin rastreadores\nKrypta no contiene herramientas de análisis, ni publicidad, ni rastreadores (0 de 432 rastreadores conocidos).\n\n6. Cesión de datos\nNo se ceden datos personales a terceros. Se utiliza Google Firebase como proveedor de infraestructura (autenticación anónima y notificaciones push).\n\n7. Borrado de datos\nPuedes borrar de forma irreversible todos tus datos en cualquier momento:\n• En los ajustes, mediante «Borrar todo»\n• Introduciendo el código de borrado en la calculadora\nEsto destruye todos los datos locales, las claves y los datos del servidor.\n\n8. Tus derechos (RGPD)\nTienes derecho de acceso, rectificación, supresión y portabilidad de los datos. Contáctanos en: https://connexa-gmbh.ch\n\n9. Cambios\nEsta política de privacidad puede actualizarse. La versión vigente siempre está disponible en la aplicación.';

  @override
  String get tutStartSetup => 'Iniciar configuración';

  @override
  String get tutWelcomeTitle => 'Bienvenido a Krypta';

  @override
  String get tutWelcomeBody =>
      'Krypta es una mensajería secreta.\n\nPara los demás, la aplicación parece una calculadora corriente: nadie sospechará que detrás se esconde un chat cifrado.\n\nTe recomendamos leer este tutorial con atención.';

  @override
  String get tutSecretCodeTitle => 'Tu código secreto';

  @override
  String get tutSecretCodeBody =>
      'Durante la configuración eliges un código numérico.\n\nEse código es tu llave: es la única forma de abrir la mensajería oculta.';

  @override
  String get tutDeleteCodeBody =>
      'El segundo código es para emergencias.\n\nAl introducirlo se borra todo de inmediato: mensajes, claves, cuenta. De forma irreversible.\n\nElige un código que no vayas a introducir por accidente.';

  @override
  String get tutDeleteCodeWarning =>
      'Todo se borra de inmediato.\nNo hay forma de recuperarlo.';

  @override
  String get tutOpenMessengerTitle => 'Abrir la mensajería';

  @override
  String get tutOpenMessengerBody =>
      'Para abrir tu mensajería:\n\n1. Introduce tu código secreto en la calculadora\n2. Pulsa la tecla =\n\nLa mensajería se abre al instante.';

  @override
  String get tutPressEquals => 'Pulsa =';

  @override
  String get tutMessengerUnlocked => 'Mensajería desbloqueada';

  @override
  String get tutVaultBody =>
      'En los ajustes puedes activar una contraseña adicional.\n\nDespués del código secreto se pedirá también la contraseña de la bóveda: doble seguridad para tus mensajes.';

  @override
  String get tutAddContactsTitle => 'Añadir contactos';

  @override
  String get tutAddContactsBody =>
      'Hay dos formas de añadir contactos:\n\n• Escanear un código QR: rápido y sencillo\n• Introducir un ID de usuario: cuando no estáis en el mismo sitio\n\nDespués ya podéis escribiros.';

  @override
  String get tutQrFast => 'Rápido y sencillo';

  @override
  String get tutEnterUserId => 'Introducir ID de usuario';

  @override
  String get tutForRemoteContacts => 'Para contactos a distancia';

  @override
  String get tutEmergencyBody =>
      'En la aplicación encontrarás botones rojos de emergencia.\n\nBorran todo de inmediato, igual que el código de borrado. Úsalos solo cuando de verdad haga falta.';

  @override
  String get tutInSettings => 'En los ajustes';

  @override
  String get tutChatFeaturesIntro =>
      'Un chat te ofrece tres funciones especiales:';

  @override
  String get tutLockMessageDesc =>
      'Proteger mensajes concretos con una contraseña';

  @override
  String get tutAutoDeleteDesc =>
      'Los mensajes se borran solos tras un tiempo definido';

  @override
  String get tutBurnAfterReadDesc =>
      'El mensaje se borra justo después de leerlo';

  @override
  String get tutReadyTitle => '¡Todo listo!';

  @override
  String get tutReadyBody =>
      'Ya sabes todo lo que necesitas.\n\nEn el siguiente paso configuras tus códigos; después tu mensajería estará lista para usar.';

  @override
  String get language => 'Idioma';

  @override
  String get chooseLanguage => 'Elige tu idioma';

  @override
  String get deviceSecuritySection => 'Seguridad del dispositivo';

  @override
  String get tutDeleteCodeTitle => 'Código de emergencia';

  @override
  String get tutEmergencyTitle => 'Botones de emergencia';

  @override
  String get tutChatFeaturesTitle => 'Funciones del chat';

  @override
  String get blockContact => 'Bloquear';

  @override
  String get authentication => 'Autenticación';

  @override
  String get contactRequestTitle => 'Solicitud de contacto';

  @override
  String get contactRequestIncomingHint =>
      'Esta persona quiere escribirte. Solo podréis escribiros cuando la aceptes.';

  @override
  String get acceptRequest => 'Aceptar';

  @override
  String get declineRequest => 'Rechazar';

  @override
  String get contactRequestSent => 'Solicitud enviada';

  @override
  String get contactRequestWaitingHint =>
      'Podrás escribir en cuanto la otra persona acepte.';

  @override
  String get resendRequest => 'Solicitar de nuevo';

  @override
  String get acceptToReply => 'Acepta la solicitud para responder';

  @override
  String get requestBadge => 'Solicitud';

  @override
  String get blockContactConfirm =>
      '¿Bloquear a esta persona? No podrá escribirte y no se le informará.';

  @override
  String get unblockContact => 'Desbloquear';

  @override
  String get contactBlocked => 'Bloqueado';

  @override
  String get minute1 => '1 minuto';

  @override
  String get welcomeBack => 'Bienvenido de nuevo';

  @override
  String get minutes30 => '30 minutos';

  @override
  String get screenshotByYou => 'Has hecho una captura del chat';

  @override
  String screenshotByPeer(String name) {
    return '$name ha hecho una captura del chat';
  }

  @override
  String get recordingByYou => 'Estás grabando la pantalla';

  @override
  String recordingByPeer(String name) {
    return '$name está grabando la pantalla';
  }

  @override
  String get screenshotNotice => 'Aviso de capturas';

  @override
  String get screenshotNoticeDescription =>
      'Ambas partes son informadas de capturas y grabaciones';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get legalSection => 'Aspectos legales';

  @override
  String get identityTitle => 'Identidad';

  @override
  String get identityVerified => 'Verificado';

  @override
  String get identityBadge => 'Seguro';

  @override
  String get scanSafetyNumber => 'Escanear código';

  @override
  String get safetyNumberScanHint =>
      'Apunta la cámara al número de seguridad de tu contacto';

  @override
  String safetyNumberMatches(String name) {
    return 'Los números coinciden: $name está verificado.';
  }

  @override
  String get safetyNumberDiffers => 'Los números no coinciden.';

  @override
  String get safetyNumberDiffersHint =>
      'Puede que alguien esté interceptando esta conversación. No envíes nada confidencial hasta comprobarlo en persona.';

  @override
  String get safetyNumberNotRecognised =>
      'Eso no es un número de seguridad. Escanea el código que aparece bajo el número de seguridad de tu contacto.';

  @override
  String get verifiedContact => 'verificado';
}
