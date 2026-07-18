import '../entities/customer.dart';

abstract class CustomerRepository {
  Stream<List<Customer>> watchAll();

  Future<Customer?> fetchById(String id);

  Future<void> upsert(Customer customer);

  Future<void> delete(String id);
}
