class EnterpriseConfig {
  const EnterpriseConfig({
    this.name = 'V&\$ INVERSIONES',
    this.phone = '',
    this.nit = '',
    this.email = '',
    this.bankAccount = '',
    this.showPhone = false,
    this.showNit = false,
    this.showEmail = false,
    this.showBankAccount = false,
    this.mora = 20,
  });

  final String name;
  final String phone;
  final String nit;
  final String email;
  final String bankAccount;
  final bool showPhone;
  final bool showNit;
  final bool showEmail;
  final bool showBankAccount;
  final int mora;
}
