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
  String get qrShareHint =>
      'Otros pueden escanear este código QR para añadirte como contacto.';

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
  String get awaitingUnlock => 'Visible una vez desbloqueado';

  @override
  String get unblockToSend =>
      'Desbloquea a este contacto para enviar mensajes.';

  @override
  String selfDestructSetTo(String dauer) {
    return 'Autodestrucción establecida en $dauer';
  }

  @override
  String get selfDestructTurnedOff => 'Autodestrucción desactivada';

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
      'Por fuera, una calculadora. Detrás están tus mensajes, cifrados.';

  @override
  String get tutAddContactsTitle => 'Añadir contactos';

  @override
  String get tutChatFeaturesIntro => 'Cada mensaje puede borrarse solo.';

  @override
  String get tutLockMessageDesc =>
      'Una contraseña solo para este mensaje. Dila de viva voz.';

  @override
  String get tutAutoDeleteDesc =>
      'Desaparece tras el tiempo que fijes, en ambos lados.';

  @override
  String get tutBurnAfterReadDesc =>
      'Se va en cuanto la otra parte sale del chat.';

  @override
  String get tutReadyTitle => 'Listo';

  @override
  String get tutReadyBody => 'Falta un punto. Es el más importante.';

  @override
  String get language => 'Idioma';

  @override
  String get chooseLanguage => 'Elige tu idioma';

  @override
  String get deviceSecuritySection => 'Seguridad del dispositivo';

  @override
  String get tutChatFeaturesTitle => 'Mensajes';

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

  @override
  String accountGone(String name) {
    return '$name ya no existe';
  }

  @override
  String get accountGoneCannotWrite =>
      'Esta cuenta ya no existe: aquí no se puede escribir.';

  @override
  String get identityKeyConfirmed => 'Clave de seguridad confirmada';

  @override
  String get identityNotConfirmed => 'Contacto no confirmado';

  @override
  String get identityConfirmedHint =>
      'La clave de seguridad de este contacto se ha comprobado con tu dispositivo. Eso confirma la clave, no quién tiene el teléfono.';

  @override
  String get identityNotConfirmedHint =>
      'Vuestros mensajes están cifrados de extremo a extremo en cualquier caso. Compara el código QR o el número de seguridad para confirmar también la clave de seguridad.';

  @override
  String get identityAlreadyConfirmed => 'Clave de seguridad ya confirmada';

  @override
  String scanContactQr(String name) {
    return 'Escanear el código QR de $name';
  }

  @override
  String get blockKeepsVerification =>
      'El estado de seguridad guardado se conserva.';

  @override
  String unblockedVerified(String name) {
    return '$name ha sido desbloqueado. El contacto sigue confirmado.';
  }

  @override
  String unblockedUnverified(String name) {
    return '$name ha sido desbloqueado. La clave de seguridad aún no se ha confirmado.';
  }

  @override
  String unblockedKeyChanged(String name) {
    return '$name ha sido desbloqueado. La clave de seguridad ha cambiado y debe confirmarse de nuevo.';
  }

  @override
  String get tutDCalculator =>
      'La calculadora funciona de verdad. Nada la delata.';

  @override
  String get tutTEncrypted => 'De extremo a extremo';

  @override
  String get tutDEncrypted =>
      'Solo tú y tu contacto podéis leer. El servidor no ve nada.';

  @override
  String get tutDLanguage => 'Siete idiomas. Se cambian en cualquier momento.';

  @override
  String get tutAccessTitle => 'Tu acceso';

  @override
  String get tutAccessIntro =>
      'Cuatro cosas protegen el mensajero. Las configuras ahora.';

  @override
  String get tutTSecretCode => 'Código secreto';

  @override
  String get tutDSecretCode =>
      'Escríbelo en la calculadora y pulsa igual. El mensajero se abre.';

  @override
  String get tutTDeleteCode => 'Código de borrado';

  @override
  String get tutDDeleteCode =>
      'Un segundo código. Borra todo al instante, sin preguntar.';

  @override
  String get tutDVault =>
      'Una contraseña adicional tras el código. Opcional, pero recomendable.';

  @override
  String get tutDScreenLock =>
      'Face ID en lugar de escribir. La app se bloquea sola al dejarla.';

  @override
  String get tutContactsIntro =>
      'Dos formas de añadir. Y una para estar seguro.';

  @override
  String get tutDAddById =>
      'Intercambia tu ID e introdúcela. También funciona a distancia.';

  @override
  String get tutTRequest => 'Solicitud';

  @override
  String get tutDRequest =>
      'La otra parte debe aceptar tu solicitud antes de que podáis chatear.';

  @override
  String get tutDQr =>
      'Muestra o escanea un código QR para añadir contactos directamente.';

  @override
  String get tutDSafetyNumber =>
      'Compara los números de seguridad para verificar quién es tu contacto y el cifrado de extremo a extremo.';

  @override
  String get tutTRemaining => 'Tiempo restante';

  @override
  String get tutDRemaining => 'Bajo el mensaje corre el tiempo que queda.';

  @override
  String get tutProtectTitle => 'Protección';

  @override
  String get tutProtectIntro => 'Lo que ocurre en un chat queda a la vista.';

  @override
  String get tutDScreenshot =>
      'La otra parte ve capturas y grabaciones. Siempre.';

  @override
  String get tutDBlock => 'Ya no pasa nada. La confirmación se conserva.';

  @override
  String get tutDClear =>
      'Vacía el historial. Tus mensajes también desaparecen allí.';

  @override
  String get tutDDeleteChat =>
      'Elimina el chat entero. La otra parte se entera.';

  @override
  String get tutTEmergency => 'Borrado de emergencia';

  @override
  String get tutDEmergency =>
      'Borra todo en el acto. Tus contactos se enteran.';

  @override
  String get tutDSettings => 'Idioma, caja fuerte y códigos se cambian ahí.';

  @override
  String get tutTAgain => 'Esta introducción';

  @override
  String get tutDAgain =>
      'Está en los ajustes. Puedes releerla cuando quieras.';

  @override
  String get onceOnlyMessage => 'Mensaje de una sola vez';
}
