abstract final class ApiEndpoints {
  // Cloud API paths are relative to the configured server URL.
  static const branchToken = 'api/get_branch_token';
  static const login = 'mobileapp/login';
  static const checkActiveApp = 'mobileapp/user/check_active_app';
  static const downloadCategories = 'mobileapp/category/download';
  static const downloadCustomers = 'mobileapp/customer/download';
  static const downloadUnits = 'mobileapp/unit/download';
  static const downloadStockUnitRates = 'mobileapp/stock_unit_rates/download';
  static const getProductUnitsAndAddons = 'mobileapp/product_unit/get_prd_unit_and_addon';
  static const getPosProductUnitsAndAddons = 'mobileapp/pos/get_product_unit_and_addon';
  static const getProducts = 'mobileapp/pos/get_product_list';
  static const getTables = 'mobileapp/pos/get_pos_table';
  static const listFavorites = 'mobileapp/pos/list_favorite';
  static const getVatType = 'mobileapp/sales_settings/vat_type';
  static const getBranchCashAccounts = 'mobileapp/sales/get_branch_all_cash_account';
  static const getBranchBankAccounts = 'mobileapp/sales/get_branch_bank_account';
  static const getCaptains = 'mobileapp/sales/get_all_captains';
  static const getUpiSettings = 'mobileapp/general_settings/get_upi_enable_status_and_upi_id';
  static const createSalesOrder = 'mobileapp/pos/add_sales_order';
  static const updateSalesOrder = 'mobileapp/pos/update_sales_order';
  static const cancelSalesOrder = 'mobileapp/pos/cancel_sales_order';
  static const settleSalesOrder = 'mobileapp/pos/settle_sales_order';
  static const listOrders = 'mobileapp/pos/get_pos_order_list';
  static const listSoldOrders = 'mobileapp/pos/get_sold_pos_order_list';
  static const getSoldOrderDetails = 'mobileapp/pos/get_sold_pos_data';
  static const getOrderDetails = 'mobileapp/pos/get_sale_order_details_pos';

  // The local hub client and router share these paths.
  static const hubStatus = '/hub/status';
  static const hubHealth = '/health';
  static const hubRegisterDevice = '/device/register';
  static const hubPrinterAssignments = '/printers/assignments';
  static const hubCreateOrder = '/orders/create';
  static const hubUpdateOrder = '/orders/update';
  static const hubListOrders = '/orders/list';
  static const hubListSoldOrders = '/orders/sold';
  static const hubOrderDetails = '/orders/details';
  static const hubTables = '/master/tables';
  static const hubCategories = '/master/categories';
  static const hubCaptains = '/master/captains';
  static const hubProducts = '/master/products';
  static const hubProductUnits = '/master/product-units';
  static const hubCreateKot = '/kot/create';
}
