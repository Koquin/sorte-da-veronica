import '../models/app_user.dart';

const List<AppUser> mockUsers = [
  AppUser(
    id: 1,
    login: 'veronica',
    password: '123',
    name: 'Veronica',
    isAdmin: true,
  ),
  AppUser(
    id: 2,
    login: 'vendedor1',
    password: '123',
    name: 'Carlos',
    isAdmin: false,
  ),
  AppUser(
    id: 3,
    login: 'vendedor2',
    password: '123',
    name: 'Mariana',
    isAdmin: false,
  ),
  AppUser(
    id: 4,
    login: 'vendedor3',
    password: '123',
    name: 'Joao',
    isAdmin: false,
  ),
];
