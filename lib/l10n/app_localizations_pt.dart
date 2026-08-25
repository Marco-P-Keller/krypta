// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'Krypta ECC';

  @override
  String get calculator => 'Calculadora';

  @override
  String get messenger => 'Mensagens';

  @override
  String get settings => 'Definições';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contactos';

  @override
  String get setupTitle => 'Bem-vindo ao Krypta ECC';

  @override
  String get setupSubtitle => 'Configure os seus códigos secretos para começar';

  @override
  String get secretCodeLabel => 'Código secreto';

  @override
  String get secretCodeHint =>
      'Introduza o código que desbloqueia as suas mensagens';

  @override
  String get decoyCodeLabel => 'Código de disfarce';

  @override
  String get decoyCodeHint =>
      'Introduza um código que abre uma aplicação de mensagens falsa';

  @override
  String get deleteCodeLabel => 'Código de eliminação';

  @override
  String get deleteCodeHint =>
      'Introduza um código que apaga todos os dados de imediato';

  @override
  String get setupComplete => 'Configuração concluída';

  @override
  String get setupContinue => 'Continuar';

  @override
  String get setupCodesInfo =>
      'Todos os códigos têm de ser diferentes e ter pelo menos 4 dígitos';

  @override
  String get back => 'Voltar';

  @override
  String get next => 'Seguinte';

  @override
  String get newChat => 'Nova conversa';

  @override
  String get typeMessage => 'Escreva uma mensagem...';

  @override
  String get send => 'Enviar';

  @override
  String get delivered => 'Entregue';

  @override
  String get sent => 'Enviada';

  @override
  String get read => 'Lida';

  @override
  String get typing => 'a escrever...';

  @override
  String get selfDestructTimer => 'Temporizador de autodestruição';

  @override
  String get seconds30 => '30 segundos';

  @override
  String get minutes5 => '5 minutos';

  @override
  String get hour1 => '1 hora';

  @override
  String get day1 => '1 dia';

  @override
  String get week1 => '1 semana';

  @override
  String get off => 'Desligado';

  @override
  String get emergencyDelete => 'Eliminação de emergência';

  @override
  String get emergencyDeleteDescription =>
      'Apaga de imediato todos os dados e chaves e termina a sessão';

  @override
  String get allDataDeleted => 'Todos os dados foram apagados';

  @override
  String get settingsTitle => 'Definições';

  @override
  String get securitySettings => 'Segurança';

  @override
  String get changeSecretCode => 'Alterar o código secreto';

  @override
  String get changeDecoyCode => 'Alterar o código de disfarce';

  @override
  String get changeDeleteCode => 'Alterar o código de eliminação';

  @override
  String get biometricUnlock => 'Desbloqueio biométrico';

  @override
  String get biometricDescription =>
      'Exigir Face ID ou impressão digital após a introdução do código';

  @override
  String get autoDeleteMessages => 'Eliminação automática de mensagens';

  @override
  String get accountSection => 'Conta';

  @override
  String get privacySection => 'Privacidade';

  @override
  String get dangerZone => 'Zona de risco';

  @override
  String get deleteAccount => 'Eliminar conta e dados';

  @override
  String get about => 'Acerca do Krypta ECC';

  @override
  String version(String version) {
    return 'Versão $version';
  }

  @override
  String get noChats => 'Ainda não há conversas';

  @override
  String get noChatsSubtitle =>
      'Inicie uma nova conversa para trocar mensagens em segurança';

  @override
  String get decoyTitle => 'Mensagens';

  @override
  String get encryptionInfo => 'As mensagens são cifradas de ponta a ponta';

  @override
  String get anonymousUser => 'Utilizador anónimo';

  @override
  String get userIdLabel => 'O seu ID';

  @override
  String get userIdCopied =>
      'ID de utilizador copiado para a área de transferência';

  @override
  String get addContactById => 'Adicionar contacto por ID';

  @override
  String get contactIdHint => 'Introduza o ID do contacto';

  @override
  String get addContact => 'Adicionar contacto';

  @override
  String get cannotAddYourself => 'Não se pode adicionar a si próprio';

  @override
  String get userNotFound => 'Utilizador não encontrado';

  @override
  String get myQrCode => 'O meu código QR';

  @override
  String get scanQrCode => 'Ler código QR';

  @override
  String get scanQr => 'Ler QR';

  @override
  String get qrScanHint => 'Aponte a câmara para um código QR do Krypta';

  @override
  String get qrShareHint => 'Deixe que os outros o leiam para se ligarem';

  @override
  String get yourQrCode => 'O seu código QR';

  @override
  String get idCopied => 'ID copiado';

  @override
  String get qrWebUnavailable =>
      'A leitura de códigos QR não está disponível na web.\nUse um dispositivo móvel para ler códigos QR.';

  @override
  String get thatsYourOwnId => 'Esse é o seu próprio ID';

  @override
  String get renameChat => 'Mudar o nome da conversa';

  @override
  String get chatName => 'Nome da conversa';

  @override
  String get save => 'Guardar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get skip => 'Ignorar';

  @override
  String get deleteChat => 'Eliminar conversa';

  @override
  String get clearChat => 'Limpar conversa';

  @override
  String clearChatConfirm(String name) {
    return 'Eliminar todas as mensagens deste chat? No dispositivo de $name desaparecem também as mensagens que enviaste — as dele mantêm-se. Isto não pode ser anulado.';
  }

  @override
  String get autoDeleteTimer => 'Temporizador de eliminação automática';

  @override
  String get autoDeleteHint =>
      'As novas mensagens desta conversa autodestroem-se após o tempo escolhido.';

  @override
  String get chatDefault => 'Predefinição da conversa';

  @override
  String chatDefaultWithTimer(String timer) {
    return 'Predefinição da conversa ($timer)';
  }

  @override
  String messagesAutoDelete(String timer) {
    return 'As mensagens são eliminadas automaticamente após $timer';
  }

  @override
  String get onlyVisibleToYou => 'Visível apenas para si';

  @override
  String get burnAfterRead => 'Destruir depois de ler';

  @override
  String get passwordProtected => 'Protegida por palavra-passe';

  @override
  String get lockMessage => 'Bloquear mensagem';

  @override
  String get lockMessageHint =>
      'Defina uma palavra-passe para a próxima mensagem. O destinatário terá de a introduzir para a ler.';

  @override
  String get enterPassword => 'Introduza a palavra-passe';

  @override
  String get setPassword => 'Definir palavra-passe';

  @override
  String get passwordRequired => 'Palavra-passe necessária';

  @override
  String get passwordRequiredHint =>
      'Introduza a palavra-passe para decifrar esta mensagem.';

  @override
  String get password => 'Palavra-passe';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get unlocked => 'Desbloqueado';

  @override
  String get wrongPassword => 'Palavra-passe incorreta';

  @override
  String get tapToUnlock => 'Toque para desbloquear';

  @override
  String get nameThisContact => 'Dê um nome a este contacto';

  @override
  String get nameContactHint =>
      'Atribua um nome a este contacto para saber quem é. Só você vê esta etiqueta.';

  @override
  String get nameContactPlaceholder => 'p. ex. Alex, mãe, trabalho...';

  @override
  String get selfDestructTimerLabel => 'Temporizador de autodestruição';

  @override
  String get vaultPassword => 'Palavra-passe do cofre';

  @override
  String get vaultPasswordDescription =>
      'Exigir uma palavra-passe forte após o código, antes de aceder às mensagens';

  @override
  String get vaultPasswordTitle => 'Cofre bloqueado';

  @override
  String get vaultPasswordHint =>
      'Introduza a palavra-passe do cofre para aceder às mensagens.';

  @override
  String get setVaultPassword => 'Definir palavra-passe do cofre';

  @override
  String get changeVaultPassword => 'Alterar palavra-passe do cofre';

  @override
  String get removeVaultPassword => 'Remover palavra-passe do cofre';

  @override
  String get vaultPasswordSet => 'Palavra-passe do cofre definida';

  @override
  String get vaultPasswordRemoved => 'Palavra-passe do cofre removida';

  @override
  String get vaultPasswordRules =>
      'Pelo menos 10 caracteres, com maiúscula, minúscula, número e carácter especial.';

  @override
  String get newPassword => 'Nova palavra-passe';

  @override
  String get confirmPassword => 'Confirmar palavra-passe';

  @override
  String get passwordsDoNotMatch => 'As palavras-passe não coincidem';

  @override
  String get passwordTooWeak => 'A palavra-passe não cumpre os requisitos';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado';

  @override
  String get delete => 'Eliminar';

  @override
  String get deleteMessage => 'Eliminar mensagem';

  @override
  String get deleteMessageConfirm =>
      'Esta mensagem será eliminada definitivamente deste dispositivo.';

  @override
  String get deleteForMe => 'Eliminar para mim';

  @override
  String get deleteForEveryone => 'Eliminar para todos';

  @override
  String get deleteForEveryoneConfirm =>
      'Esta mensagem será eliminada tanto para si como para o destinatário.';

  @override
  String get qrInvalidFormat =>
      'Formato de código QR inválido. Só são aceites códigos QR do Krypta.';

  @override
  String get qrUnsupportedVersion =>
      'Versão de código QR não suportada. Atualize a aplicação.';

  @override
  String get qrFingerprintMismatch =>
      'Aviso de segurança: a impressão digital do código QR foi adulterada. Operação cancelada.';

  @override
  String get qrKeyMismatch =>
      'AVISO DE SEGURANÇA: a chave do servidor NÃO corresponde à do código QR. Possível ataque detetado. O contacto foi bloqueado.';

  @override
  String get qrVerified => 'Chave verificada';

  @override
  String get verificationStale => 'A verificação tem mais de 90 dias';

  @override
  String get verifyNow => 'Verificar novamente';

  @override
  String get showTutorial => 'Ver o tutorial outra vez';

  @override
  String get showTutorialSubtitle => 'Repetir a introdução';

  @override
  String get openSourceLicenses => 'Licenças de código aberto';

  @override
  String get openSourceLicensesSubtitle => 'Bibliotecas de terceiros e avisos';

  @override
  String get aboutClose => 'Fechar';

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
      other: 'Restam $remaining tentativas',
      one: 'Resta 1 tentativa',
    );
    return 'Palavra-passe incorreta. $_temp0 antes de todos os dados serem apagados.';
  }

  @override
  String get keysNotPublishedDenied =>
      'O servidor recusou as suas chaves – ninguém lhe consegue escrever.';

  @override
  String get keysNotPublishedFailed =>
      'Não foi possível publicar as suas chaves – ninguém lhe consegue escrever.';

  @override
  String get biometricUnlockReason => 'Desbloquear o Krypta Messenger';

  @override
  String get deviceCompromised => 'O dispositivo pode estar comprometido.';

  @override
  String get deviceCompromisedDegraded =>
      'O dispositivo pode estar comprometido. Segurança por hardware desativada.';

  @override
  String get fieldRequired => 'Obrigatório';

  @override
  String codeMinDigits(int count) {
    return 'Pelo menos $count dígitos';
  }

  @override
  String get codeDigitsOnly => 'Apenas dígitos';

  @override
  String get deleteCodeMustDiffer =>
      'O código de eliminação tem de ser diferente do código secreto.';

  @override
  String get setupFailed => 'A configuração falhou. Tente novamente.';

  @override
  String get setupSecretCodeSubtitle =>
      'Introduza-o na calculadora para abrir o seu cofre.';

  @override
  String get setupDeleteCodeSubtitle =>
      'Apaga tudo de imediato. Use apenas em emergências.';

  @override
  String get contactKeyChangedWarning =>
      'A chave de segurança deste contacto mudou. As mensagens ficam bloqueadas até verificar a identidade dele. Leia o código QR ou comparem os números de segurança para retomar a conversa.';

  @override
  String get verifyIdentity => 'Verificar identidade';

  @override
  String get safetyNumberCompareHint =>
      'Comparem os números de segurança ou leiam os códigos QR para verificar a cifra de ponta a ponta.';

  @override
  String get viewSafetyNumber => 'Ver número de segurança';

  @override
  String get safetyNumberTitle => 'Número de segurança';

  @override
  String get safetyNumberCopied => 'Número de segurança copiado';

  @override
  String get safetyNumberMatchHint =>
      'Compare este número com o do seu contacto. Se coincidirem, a vossa conversa é segura.';

  @override
  String get verificationFailedKeyMismatch =>
      'A verificação falhou – as chaves não coincidem';

  @override
  String get markVerified => 'Marcar como verificado';

  @override
  String get securitySettingsReason => 'Alterar as definições de segurança';

  @override
  String get vaultPasswordReAuthHint =>
      'Introduza a palavra-passe do cofre para alterar as definições de segurança.';

  @override
  String get codeAlreadyInUse => 'Este código já está a ser usado noutra ação.';

  @override
  String get deviceSecure => 'Dispositivo seguro';

  @override
  String get deviceCompromisedDetected => 'Comprometimento detetado';

  @override
  String get deviceStatusUnknown => 'Estado desconhecido';

  @override
  String get deviceSecureSubtitle => 'Sem indícios de root, jailbreak ou Frida';

  @override
  String get deviceCompromisedSubtitle =>
      'Root, jailbreak ou instrumentação detetados. Segurança por hardware desativada.';

  @override
  String get deviceStatusUnknownSubtitle =>
      'A verificação de integridade falhou – modo restrito ativo.';

  @override
  String get hardwareEnclave => 'Enclave de hardware';

  @override
  String get hardwareTee => 'Armazenamento de chaves TEE';

  @override
  String get hardwareSoftware => 'Armazenamento de chaves por software';

  @override
  String get hardwareBoundSubtitle =>
      'Chave da base de dados associada ao hardware';

  @override
  String get hardwareEnclaveSubtitle => 'StrongBox/Secure Enclave disponível';

  @override
  String get hardwareTeeSubtitle =>
      'Chave guardada no Trusted Execution Environment';

  @override
  String get hardwareSoftwareSubtitle =>
      'Não há segurança por hardware disponível';

  @override
  String get pushPrivacy => 'Privacidade das notificações';

  @override
  String get pushPrivacyOn => 'Ativada – as mensagens são obtidas por sondagem';

  @override
  String get pushPrivacyOff => 'Desativada – notificações push ativas';

  @override
  String get readReceipts => 'Confirmações de leitura';

  @override
  String get readReceiptsOn => 'Ativadas – o remetente vê quando lê';

  @override
  String get readReceiptsOff => 'Desativadas – privacidade máxima';

  @override
  String get deliveryReceipts => 'Confirmações de entrega';

  @override
  String get deliveryReceiptsOn =>
      'Ativadas – o remetente vê quando é entregue';

  @override
  String get deliveryReceiptsOff => 'Desativadas – privacidade máxima';

  @override
  String get privacyPolicyBody =>
      'Krypta ECC — Política de privacidade\n\nÚltima atualização: abril de 2026\n\n1. Responsável pelo tratamento\nConnexa GmbH\nContacto: https://connexa-gmbh.ch\n\n2. Que dados são recolhidos?\nO Krypta recolhe tão poucos dados quanto é tecnicamente possível:\n• ID anónimo do Firebase (sem e-mail, sem nome, sem número de telefone)\n• Chave pública de cifra (X25519)\n• Token push do FCM (para as notificações)\n\n3. Cifra\nTodas as mensagens são cifradas de ponta a ponta (protocolo Signal: X3DH + Double Ratchet). Em momento algum o servidor tem acesso ao texto simples das suas mensagens. Cifra: XChaCha20-Poly1305. Hashing de palavras-passe: Argon2id.\n\n4. Armazenamento de dados\n• As mensagens são guardadas apenas no seu dispositivo (cifradas)\n• O servidor funciona apenas como retransmissor temporário — as mensagens são eliminadas após a entrega\n• As chaves são guardadas no Porta-chaves do iOS / Android Keystore\n\n5. Sem rastreadores\nO Krypta não contém ferramentas de análise, publicidade nem rastreadores (0 de 432 rastreadores conhecidos).\n\n6. Transmissão de dados\nNão são transmitidos dados pessoais a terceiros. É utilizado o Google Firebase como fornecedor de infraestrutura (autenticação anónima e notificações push).\n\n7. Eliminação de dados\nPode eliminar de forma irreversível todos os seus dados a qualquer momento:\n• Nas definições, através de «Eliminar tudo»\n• Introduzindo o código de eliminação na calculadora\nIsto destrói todos os dados locais, as chaves e os dados no servidor.\n\n8. Os seus direitos (RGPD)\nTem direito de acesso, retificação, apagamento e portabilidade dos dados. Contacte-nos através de: https://connexa-gmbh.ch\n\n9. Alterações\nEsta política de privacidade pode ser atualizada. A versão em vigor está sempre disponível na aplicação.';

  @override
  String get tutStartSetup => 'Iniciar configuração';

  @override
  String get tutWelcomeTitle => 'Bem-vindo ao Krypta';

  @override
  String get tutWelcomeBody =>
      'O Krypta é uma aplicação de mensagens secreta.\n\nPara todos os outros, a aplicação parece uma calculadora normal — ninguém vai suspeitar que por trás se esconde uma conversa cifrada.\n\nRecomendamos que leia este tutorial com atenção.';

  @override
  String get tutSecretCodeTitle => 'O seu código secreto';

  @override
  String get tutSecretCodeBody =>
      'Durante a configuração escolhe um código numérico.\n\nEsse código é a sua chave: é a única forma de abrir as mensagens ocultas.';

  @override
  String get tutDeleteCodeBody =>
      'O segundo código é para emergências.\n\nAo introduzi-lo, tudo é apagado de imediato: mensagens, chaves, conta. De forma irreversível.\n\nEscolha um código que não introduza por engano.';

  @override
  String get tutDeleteCodeWarning =>
      'Tudo é apagado de imediato.\nNão há qualquer recuperação possível.';

  @override
  String get tutOpenMessengerTitle => 'Abrir as mensagens';

  @override
  String get tutOpenMessengerBody =>
      'Para abrir as suas mensagens:\n\n1. Introduza o código secreto na calculadora\n2. Prima a tecla =\n\nAs mensagens abrem-se de imediato.';

  @override
  String get tutPressEquals => 'Prima =';

  @override
  String get tutMessengerUnlocked => 'Mensagens desbloqueadas';

  @override
  String get tutVaultBody =>
      'Nas definições pode ativar uma palavra-passe adicional.\n\nDepois do código secreto passa a ser pedida também a palavra-passe do cofre — dupla segurança para as suas mensagens.';

  @override
  String get tutAddContactsTitle => 'Adicionar contactos';

  @override
  String get tutAddContactsBody =>
      'Há duas formas de adicionar contactos:\n\n• Ler um código QR — rápido e simples\n• Introduzir um ID de utilizador — quando não estão no mesmo sítio\n\nDepois disso já se podem escrever.';

  @override
  String get tutQrFast => 'Rápido e simples';

  @override
  String get tutEnterUserId => 'Introduzir ID de utilizador';

  @override
  String get tutForRemoteContacts => 'Para contactos à distância';

  @override
  String get tutEmergencyBody =>
      'Na aplicação encontra botões vermelhos de emergência.\n\nApagam tudo de imediato — tal como o código de eliminação. Use-os apenas quando for mesmo necessário.';

  @override
  String get tutInSettings => 'Nas definições';

  @override
  String get tutChatFeaturesIntro =>
      'Numa conversa tem três funções especiais:';

  @override
  String get tutLockMessageDesc =>
      'Proteger mensagens individuais com uma palavra-passe';

  @override
  String get tutAutoDeleteDesc =>
      'As mensagens apagam-se sozinhas após um tempo definido';

  @override
  String get tutBurnAfterReadDesc =>
      'A mensagem é eliminada logo depois de ser lida';

  @override
  String get tutReadyTitle => 'Tudo pronto!';

  @override
  String get tutReadyBody =>
      'Agora já sabe tudo o que precisa.\n\nNo passo seguinte configura os seus códigos — depois disso as suas mensagens ficam prontas a usar.';

  @override
  String get language => 'Idioma';

  @override
  String get chooseLanguage => 'Escolha o seu idioma';

  @override
  String get deviceSecuritySection => 'Segurança do dispositivo';

  @override
  String get tutDeleteCodeTitle => 'Código de emergência';

  @override
  String get tutEmergencyTitle => 'Botões de emergência';

  @override
  String get tutChatFeaturesTitle => 'Funções da conversa';

  @override
  String get blockContact => 'Bloquear';

  @override
  String get authentication => 'Autenticação';

  @override
  String get contactRequestTitle => 'Pedido de contacto';

  @override
  String get contactRequestIncomingHint =>
      'Esta pessoa quer escrever-lhe. Só poderão escrever-se depois de a aceitar.';

  @override
  String get acceptRequest => 'Aceitar';

  @override
  String get declineRequest => 'Recusar';

  @override
  String get contactRequestSent => 'Pedido enviado';

  @override
  String get contactRequestWaitingHint =>
      'Poderá escrever assim que a outra pessoa aceitar.';

  @override
  String get resendRequest => 'Pedir novamente';

  @override
  String get acceptToReply => 'Aceite o pedido para responder';

  @override
  String get requestBadge => 'Pedido';

  @override
  String get blockContactConfirm =>
      'Bloquear esta pessoa? Não poderá escrever-lhe e não será informada.';

  @override
  String get unblockContact => 'Desbloquear';

  @override
  String get contactBlocked => 'Bloqueado';

  @override
  String get minute1 => '1 minuto';

  @override
  String get welcomeBack => 'Bem-vindo de volta';

  @override
  String get minutes30 => '30 minutos';

  @override
  String get screenshotByYou => 'Fez uma captura de ecrã da conversa';

  @override
  String screenshotByPeer(String name) {
    return '$name fez uma captura de ecrã da conversa';
  }

  @override
  String get recordingByYou => 'Está a gravar o ecrã';

  @override
  String recordingByPeer(String name) {
    return '$name está a gravar o ecrã';
  }

  @override
  String get screenshotNotice => 'Aviso de captura';

  @override
  String get screenshotNoticeDescription =>
      'Ambas as partes são informadas de capturas e gravações';

  @override
  String get privacyPolicy => 'Política de privacidade';

  @override
  String get legalSection => 'Informação legal';

  @override
  String get identityTitle => 'Identidade';

  @override
  String get identityVerified => 'Verificado';

  @override
  String get identityBadge => 'Seguro';

  @override
  String get scanSafetyNumber => 'Ler código';

  @override
  String get safetyNumberScanHint =>
      'Aponta a câmara para o número de segurança do teu contacto';

  @override
  String safetyNumberMatches(String name) {
    return 'Os números coincidem — $name está verificado.';
  }

  @override
  String get safetyNumberDiffers => 'Os números não coincidem.';

  @override
  String get safetyNumberDiffersHint =>
      'Alguém pode estar a intercetar esta conversa. Não envies nada confidencial até confirmarem pessoalmente.';

  @override
  String get safetyNumberNotRecognised =>
      'Isto não é um número de segurança. Lê o código que aparece no teu contacto por baixo do número de segurança.';

  @override
  String get verifiedContact => 'verificado';

  @override
  String accountGone(String name) {
    return '$name já não existe';
  }

  @override
  String get accountGoneCannotWrite =>
      'Esta conta já não existe — aqui não se pode escrever.';
}
